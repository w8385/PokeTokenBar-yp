import base64
import contextlib
import hashlib
import json
import socket
import threading
import time

import pytest
from slack_bolt import App
from slack_sdk import WebClient

from ypoke.transport import editor_options_listener, options_listener, socket_handler

RECONNECT_BUDGET = 12


class FakeSlack:
    """A local Socket Mode endpoint. The first connection says `first_frame` after hello and then dies silently (the
    socket is shut down without a closing handshake); later connections are kept open and answer pings."""

    def __init__(self, first_frame=None):
        self.first_frame = first_frame
        self.connections = []
        self._listener = socket.socket()
        self._listener.bind(("127.0.0.1", 0))
        self._listener.listen(5)
        self.url = f"wss://localhost:{self._listener.getsockname()[1]}/link"
        threading.Thread(target=self._accept, daemon=True).start()

    def close(self) -> None:
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
                time.sleep(1)
                conn.shutdown(socket.SHUT_RDWR)
                return
            while data := conn.recv(4096):
                if data[0] & 0x0F == 9:
                    conn.sendall(bytes([0x8A, 0]))
        except OSError:
            return


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


def connect(slack):
    handler = socket_handler(App(client=WebClient(token="test"), token_verification_enabled=False), "test-app-token",
                             web_client=FakeWeb(slack.url))
    handler.connect()
    return handler


def stop(handler) -> None:
    handler.client.auto_reconnect_enabled = False
    with contextlib.suppress(AttributeError):
        handler.close()


def wait_until(condition, seconds):
    deadline = time.monotonic() + seconds
    while not condition():
        if time.monotonic() > deadline:
            return False
        time.sleep(0.05)
    return True


@pytest.fixture
def slack(request):
    made = FakeSlack(getattr(request, "param", None))
    yield made
    made.close()


def test_a_link_that_dies_silently_is_replaced_within_seconds(slack):
    handler = connect(slack)
    try:
        assert wait_until(lambda: len(slack.connections) >= 2, RECONNECT_BUDGET)
    finally:
        stop(handler)


@pytest.mark.parametrize("slack", [{"type": "disconnect", "reason": "refresh_requested"}], indirect=True)
def test_the_reason_slack_gives_for_a_disconnect_is_logged(slack, caplog):
    with caplog.at_level("WARNING", logger="ypoke.transport"):
        handler = connect(slack)
        try:
            assert wait_until(lambda: "slack asked to disconnect reason=refresh_requested" in caplog.text, RECONNECT_BUDGET)
        finally:
            stop(handler)


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
