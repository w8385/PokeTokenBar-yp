import base64
import hashlib
import json
import socket
import struct
import threading

import pytest
from slack_bolt import App
from slack_sdk import WebClient
from slack_sdk.socket_mode.builtin.connection import Connection

from conftest import threads_still_running
from ypoke.transport import editor_options_listener, options_listener, socket_handler

RECONNECT_BUDGET = 12


class FakeSlack:
    """A local Socket Mode endpoint. The first link says `first_frame` after hello and dies silently (reset, without a
    closing handshake) once `drop_first` is set; later links stay open and answer pings."""

    def __init__(self, first_frame=None):
        self.first_frame = first_frame
        self.drop_first = threading.Event()
        self.connections = []
        self._listener = socket.socket()
        self._listener.bind(("127.0.0.1", 0))
        self._listener.listen(5)
        self.url = f"wss://localhost:{self._listener.getsockname()[1]}/link"
        threading.Thread(target=self._accept, daemon=True).start()

    def close(self) -> None:
        self.drop_first.set()
        for sock in [self._listener, *self.connections]:
            try:
                sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        self._listener.close()

    def _accept(self) -> None:
        while True:
            try:
                conn, _ = self._listener.accept()
            except OSError:
                return
            self.connections.append(conn)
            threading.Thread(target=self._serve, args=(conn, len(self.connections)), daemon=True).start()

    def _serve(self, conn, number: int) -> None:
        try:
            _handshake(conn)
            conn.sendall(_text_frame({"type": "hello", "num_connections": 1, "debug_info": {}}))
            if number == 1:
                if self.first_frame:
                    conn.sendall(_text_frame(self.first_frame))
                self.drop_first.wait()
                conn.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
                conn.close()
                return
            pending = b""
            while data := conn.recv(4096):
                pending += data
                while frame := _client_frame(pending):
                    opcode, payload, pending = frame
                    if opcode == 9:
                        conn.sendall(bytes([0x8A, len(payload)]) + payload)
        except OSError:
            return


def _client_frame(data: bytes) -> tuple[int, bytes, bytes] | None:
    """The first masked client frame in `data` as (opcode, payload, rest), or None until it has all arrived. Pings
    carry a session id and a time, well under the 126 bytes a one-byte length can say."""
    if len(data) < 6:
        return None
    end = 6 + (data[1] & 0x7F)
    if len(data) < end:
        return None
    mask = data[2:6]
    return data[0] & 0x0F, bytes(byte ^ mask[index % 4] for index, byte in enumerate(data[6:end])), data[end:]


def _handshake(conn) -> None:
    request = b""
    while b"\r\n\r\n" not in request:
        request += conn.recv(4096)
    key = next(line.split(b": ")[1] for line in request.split(b"\r\n") if line.lower().startswith(b"sec-websocket-key"))
    accept = base64.b64encode(hashlib.sha1(key + b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest()).decode()
    conn.sendall(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                  f"Sec-WebSocket-Accept: {accept}\r\n\r\n").encode())


def _text_frame(message: dict) -> bytes:
    data = json.dumps(message).encode()
    return bytes([0x81, len(data)]) + data


class FakeWeb(WebClient):
    def __init__(self, url):
        super().__init__(token="test")
        self._url = url

    def apps_connections_open(self, *, app_token, **kwargs):
        return {"url": self._url}


class Links:
    """The links the client has read a hello from. The client reads a link only once its session runner serves it, so
    `replaced` means the reconnect has finished, not just that the server accepted a socket."""

    def __init__(self, client):
        self.hellos = 0
        self.first = threading.Event()
        self.replaced = threading.Event()
        client.on_message_listeners.append(self._heard)

    def _heard(self, message: str) -> None:
        if json.loads(message).get("type") != "hello":
            return
        self.hellos += 1
        (self.first if self.hellos == 1 else self.replaced).set()


def connect(slack):
    handler = socket_handler(App(client=WebClient(token="test"), token_verification_enabled=False), "test-app-token",
                             web_client=FakeWeb(slack.url))
    links = Links(handler.client)
    handler.connect()
    return handler, links


def stop(handler) -> None:
    """`close()` joins the client's threads with no timeout, so it runs on its own thread and a hang fails the test."""
    closing = threading.Thread(target=handler.close, name="socket-close", daemon=True)
    closing.start()
    closing.join(RECONNECT_BUDGET)
    assert not closing.is_alive(), "SocketModeClient.close() did not return"


@pytest.fixture
def slack(request):
    made = FakeSlack(getattr(request, "param", None))
    yield made
    made.close()


def test_a_link_that_dies_silently_is_replaced_within_seconds(slack):
    handler, links = connect(slack)
    try:
        assert links.first.wait(RECONNECT_BUDGET)
        slack.drop_first.set()
        assert links.replaced.wait(RECONNECT_BUDGET)
    finally:
        stop(handler)


def test_a_replacement_counts_only_once_the_client_reads_from_it(slack, monkeypatch):
    serve = Connection.run_until_completion
    entered, release = threading.Event(), threading.Event()
    handler, links = connect(slack)
    first = handler.client.current_session

    def held(self, state):
        if self is not first:
            entered.set()
            release.wait(RECONNECT_BUDGET)
        return serve(self, state)

    monkeypatch.setattr(Connection, "run_until_completion", held)
    try:
        assert links.first.wait(RECONNECT_BUDGET)
        slack.drop_first.set()
        assert entered.wait(RECONNECT_BUDGET)
        assert len(slack.connections) == 2 and handler.client.current_session is not first
        assert not links.replaced.is_set()
        release.set()
        assert links.replaced.wait(RECONNECT_BUDGET)
    finally:
        release.set()
        stop(handler)


@pytest.mark.parametrize("slack", [{"type": "disconnect", "reason": "refresh_requested"}], indirect=True)
def test_the_reason_slack_gives_for_a_disconnect_is_logged(slack, caplog):
    with caplog.at_level("WARNING", logger="ypoke.transport"):
        handler, links = connect(slack)
        try:
            assert links.replaced.wait(RECONNECT_BUDGET)
            assert "slack asked to disconnect reason=refresh_requested" in caplog.text
        finally:
            stop(handler)


def test_a_thread_left_running_is_reported():
    before = set(threading.enumerate())
    done = threading.Event()
    left = threading.Thread(target=done.wait, name="left-running")
    left.start()
    try:
        assert threads_still_running(before, seconds=0) == ["left-running"]
    finally:
        done.set()
        left.join()
    assert threads_still_running(before, seconds=0) == []


def test_an_options_answer_is_capped_to_what_fits_a_small_socket_frame():
    options = [{"text": {"type": "plain_text", "text": f"{index}"}, "value": str(index)} for index in range(100)]
    answers = []

    class Editor:
        def options(self, user_id, block_id, query):
            return options

    class Trades:
        def suggest(self, user_id, block_id, query):
            return options

    payload = {"action_id": "a", "block_id": "b", "value": ""}
    editor_options_listener(Editor())(ack=lambda **reply: answers.append(reply), body={"user": {"id": "UA"}}, payload=payload)
    options_listener(Trades())(ack=lambda **reply: answers.append(reply), body={"user": {"id": "UA"}}, payload=payload)
    assert [len(answer["options"]) for answer in answers] == [30, 30]
    assert answers[0]["options"] == options[:30]
