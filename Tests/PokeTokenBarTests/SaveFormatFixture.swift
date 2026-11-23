/// Saves written by the current release. Never regenerate them to make a test pass.
enum SaveFormatFixture {
    /// `SaveFormatPinTests.fullState()` encoded.
    static let json = #"""
{
  "active" : {
    "baseID" : 25,
    "dittoDisguise" : 25,
    "dittoRevealed" : true,
    "evolution" : {
      "battleCursor" : 721692800,
      "candies" : 0,
      "flipped" : false,
      "graduateXP" : 0,
      "lost" : 0,
      "pets" : 3,
      "played" : 0,
      "rained" : false,
      "seenBattles" : [
        "b-1"
      ],
      "spentBaseline" : 1000000,
      "spun" : false,
      "stuckNotified" : "level",
      "tower" : "waters",
      "won" : 0
    },
    "hasGrowthBoost" : true,
    "isShiny" : true,
    "nature" : "jolly",
    "pathIDs" : [
      172,
      25
    ],
    "plannedPathIDs" : [
      172,
      25,
      26
    ],
    "prayers" : {
      "count" : 2
    },
    "profile" : {
      "abilityIsHidden" : false,
      "abilityName" : "static",
      "growthTokens" : 0,
      "instanceID" : "line-1",
      "ivs" : {
        "attack" : 1,
        "defense" : 13,
        "hp" : 29,
        "specialAttack" : 16,
        "specialDefense" : 4,
        "speed" : 14
      },
      "level" : 5,
      "mirrorHerb" : true,
      "moves" : [

      ],
      "seed" : 11
    },
    "rarity" : "uncommon",
    "stageIndex" : 1,
    "totalForms" : 3,
    "tradeGated" : true,
    "usedAtStage" : 4000
  },
  "appliedTradeIDs" : [
    "trade-1"
  ],
  "candyFeatureSeeded" : true,
  "candyGrantTier" : {
    "five_hour" : 2
  },
  "candyWindowEpoch" : {
    "five_hour" : "2023-11-14T10:00:00Z"
  },
  "claimedTodayTokensByProvider" : {
    "claude_code" : 123
  },
  "clickGrowth" : 77,
  "collectedFinals" : [
    "4-6"
  ],
  "dex" : [
    {
      "baseID" : 4,
      "caughtAt" : 721692800,
      "chainOrder" : [
        4,
        5,
        6
      ],
      "finalID" : 6,
      "id" : "grad-1",
      "isShiny" : false,
      "names" : {
        "4" : {
          "en" : "Charmander"
        },
        "5" : {
          "en" : "Charmeleon"
        },
        "6" : {
          "en" : "Charizard"
        }
      },
      "namesVersion" : 1,
      "nature" : "bold",
      "originalTrainer" : "Trainer",
      "prayers" : {
        "count" : 1
      },
      "profile" : {
        "abilityIsHidden" : false,
        "growthTokens" : 0,
        "instanceID" : "grad-1",
        "ivs" : {
          "attack" : 23,
          "defense" : 14,
          "hp" : 3,
          "specialAttack" : 9,
          "specialDefense" : 14,
          "speed" : 28
        },
        "level" : 5,
        "moves" : [

        ],
        "seed" : 12
      },
      "rarity" : "rare"
    },
    {
      "baseID" : 1,
      "caughtAt" : 721692800,
      "chainOrder" : [
        1,
        2
      ],
      "finalID" : 2,
      "id" : "stored-1",
      "isShiny" : false,
      "profile" : {
        "abilityIsHidden" : false,
        "growthTokens" : 0,
        "instanceID" : "stored-1",
        "ivs" : {
          "attack" : 17,
          "defense" : 8,
          "hp" : 31,
          "specialAttack" : 19,
          "specialDefense" : 3,
          "speed" : 4
        },
        "level" : 5,
        "moves" : [

        ],
        "seed" : 13
      },
      "rarity" : "common",
      "releasedAt" : 721692800,
      "tradeHeldItem" : "metalCoat"
    },
    {
      "baseID" : 201,
      "caughtAt" : 721692800,
      "chainOrder" : [
        201
      ],
      "finalID" : 201,
      "form" : "c",
      "id" : "grad-2",
      "isShiny" : false,
      "names" : {
        "201" : {
          "en" : "Unown"
        }
      },
      "namesVersion" : 1,
      "profile" : {
        "abilityIsHidden" : false,
        "growthTokens" : 0,
        "instanceID" : "grad-2",
        "ivs" : {
          "attack" : 26,
          "defense" : 10,
          "hp" : 30,
          "specialAttack" : 18,
          "specialDefense" : 23,
          "speed" : 30
        },
        "level" : 5,
        "moves" : [

        ],
        "seed" : 14
      },
      "rarity" : "uncommon"
    }
  ],
  "dexCompletionsSeeded" : true,
  "economyVersion" : 3,
  "eggPrayers" : {
    "count" : 4
  },
  "eggTier" : "rare",
  "eggUsage" : 1200,
  "expShareHolders" : [
    "grad-1"
  ],
  "expShareTakenOff" : [
    "stored-1"
  ],
  "friendEntryIDs" : [
    "grad-2"
  ],
  "graduateEvolution" : {
    "grad-1" : {
      "candies" : 0,
      "flipped" : false,
      "graduateXP" : 0,
      "lost" : 0,
      "pets" : 0,
      "played" : 0,
      "rained" : false,
      "seenBattles" : [

      ],
      "spentBaseline" : 20000000,
      "spun" : false,
      "won" : 0
    }
  },
  "growthMode" : "time",
  "gymBadges" : {
    "regions" : {
      "kanto" : {
        "gyms" : [
          1
        ],
        "hallOfFame" : true,
        "hiddenBeaten" : false,
        "orgBeaten" : false
      }
    }
  },
  "heldItems" : {
    "grad-1" : "leftovers"
  },
  "idleHintDismissed" : true,
  "installBaselineSet" : true,
  "inventory" : {
    "mint" : 1,
    "rareCandy" : 3
  },
  "keepWaiting" : {
    "grad-1" : 6
  },
  "language" : "ko",
  "lastDate" : "2023-11-14",
  "lastUsageAt" : 721692800,
  "leftoverEvolutionItemsReturned" : true,
  "notifiedDexCompletions" : [
    "kanto"
  ],
  "parkedSpentTokens" : 20000000,
  "pendingForm" : "b",
  "pendingHatchID" : 201,
  "raisedEntryID" : "grad-1",
  "remoteOpResults" : [
    {
      "id" : 41,
      "reason" : "no_tokens"
    }
  ],
  "remoteOpsEpoch" : "epoch-1",
  "remoteOpsLastID" : 42,
  "representativeForm" : "c",
  "representativeSpeciesID" : 201,
  "rewardedDexRegions" : [
    "kanto"
  ],
  "scoutDraws" : {
    "kanto" : [
      1,
      4,
      7
    ]
  },
  "scoutedEgg" : true,
  "shinyEgg" : true,
  "spentTokens" : 30000000,
  "storedLines" : {
    "stored-1" : {
      "mon" : {
        "baseID" : 1,
        "dittoRevealed" : false,
        "evolution" : {
          "candies" : 0,
          "flipped" : false,
          "graduateXP" : 0,
          "lost" : 0,
          "pets" : 0,
          "played" : 0,
          "rained" : false,
          "seenBattles" : [

          ],
          "spentBaseline" : 0,
          "spun" : false,
          "won" : 0
        },
        "hasGrowthBoost" : false,
        "isShiny" : false,
        "nature" : "calm",
        "pathIDs" : [
          1
        ],
        "plannedPathIDs" : [
          1
        ],
        "profile" : {
          "abilityIsHidden" : false,
          "growthTokens" : 0,
          "instanceID" : "stored-1",
          "ivs" : {
            "attack" : 17,
            "defense" : 8,
            "hp" : 31,
            "specialAttack" : 19,
            "specialDefense" : 3,
            "speed" : 4
          },
          "level" : 5,
          "moves" : [

          ],
          "seed" : 13
        },
        "rarity" : "common",
        "stageIndex" : 0,
        "totalForms" : 3,
        "usedAtStage" : 50
      },
      "spentAtStore" : 10000000
    }
  },
  "stuckWatch" : {
    "id" : "grad-1",
    "since" : 721692800
  },
  "timeCredit" : 5000000,
  "tokenModeSince" : 721692800,
  "urshifuStylesRepaired" : true,
  "usedSinceInstall" : 900000000
}
"""#

    /// What `CompanionStore` writes after loading `json`.
    static let savedJSON = #"""
{
  "active" : {
    "baseID" : 25,
    "dittoDisguise" : 25,
    "dittoRevealed" : true,
    "evolution" : {
      "battleCursor" : 721692800,
      "candies" : 0,
      "flipped" : false,
      "graduateXP" : 0,
      "lost" : 0,
      "pets" : 3,
      "played" : 0,
      "rained" : false,
      "seenBattles" : [
        "b-1"
      ],
      "spentBaseline" : 1000000,
      "spun" : false,
      "stuckNotified" : "level",
      "tower" : "waters",
      "won" : 0
    },
    "hasGrowthBoost" : true,
    "isShiny" : true,
    "nature" : "jolly",
    "pathIDs" : [
      172,
      25
    ],
    "plannedPathIDs" : [
      172,
      25,
      26
    ],
    "prayers" : {
      "count" : 2
    },
    "profile" : {
      "abilityIsHidden" : false,
      "abilityName" : "static",
      "growthTokens" : 6258000,
      "instanceID" : "line-1",
      "ivs" : {
        "attack" : 1,
        "defense" : 13,
        "hp" : 29,
        "specialAttack" : 16,
        "specialDefense" : 4,
        "speed" : 14
      },
      "level" : 20,
      "mirrorHerb" : true,
      "moves" : [

      ],
      "seed" : 11
    },
    "rarity" : "uncommon",
    "stageIndex" : 1,
    "totalForms" : 3,
    "tradeGated" : true,
    "usedAtStage" : 4000
  },
  "appliedTradeIDs" : [
    "trade-1"
  ],
  "candyFeatureSeeded" : true,
  "candyGrantTier" : {
    "five_hour" : 2
  },
  "candyWindowEpoch" : {
    "five_hour" : "2023-11-14T10:00:00Z"
  },
  "claimedTodayTokensByProvider" : {
    "claude_code" : 123
  },
  "clickGrowth" : 77,
  "collectedFinals" : [
    "4-6"
  ],
  "dex" : [
    {
      "baseID" : 4,
      "caughtAt" : 721692800,
      "chainOrder" : [
        4,
        5,
        6
      ],
      "finalID" : 6,
      "id" : "grad-1",
      "isShiny" : false,
      "names" : {
        "4" : {
          "en" : "Charmander"
        },
        "5" : {
          "en" : "Charmeleon"
        },
        "6" : {
          "en" : "Charizard"
        }
      },
      "namesVersion" : 1,
      "nature" : "bold",
      "originalTrainer" : "Trainer",
      "prayers" : {
        "count" : 1
      },
      "profile" : {
        "abilityIsHidden" : false,
        "growthTokens" : 0,
        "instanceID" : "grad-1",
        "ivs" : {
          "attack" : 23,
          "defense" : 14,
          "hp" : 3,
          "specialAttack" : 9,
          "specialDefense" : 14,
          "speed" : 28
        },
        "level" : 5,
        "moves" : [

        ],
        "seed" : 12
      },
      "rarity" : "rare"
    },
    {
      "baseID" : 1,
      "caughtAt" : 721692800,
      "chainOrder" : [
        1,
        2
      ],
      "finalID" : 2,
      "id" : "stored-1",
      "isShiny" : false,
      "profile" : {
        "abilityIsHidden" : false,
        "growthTokens" : 0,
        "instanceID" : "stored-1",
        "ivs" : {
          "attack" : 17,
          "defense" : 8,
          "hp" : 31,
          "specialAttack" : 19,
          "specialDefense" : 3,
          "speed" : 4
        },
        "level" : 5,
        "moves" : [

        ],
        "seed" : 13
      },
      "rarity" : "common",
      "releasedAt" : 721692800,
      "tradeHeldItem" : "metalCoat"
    },
    {
      "baseID" : 201,
      "caughtAt" : 721692800,
      "chainOrder" : [
        201
      ],
      "finalID" : 201,
      "form" : "c",
      "id" : "grad-2",
      "isShiny" : false,
      "names" : {
        "201" : {
          "en" : "Unown"
        }
      },
      "namesVersion" : 1,
      "profile" : {
        "abilityIsHidden" : false,
        "growthTokens" : 0,
        "instanceID" : "grad-2",
        "ivs" : {
          "attack" : 26,
          "defense" : 10,
          "hp" : 30,
          "specialAttack" : 18,
          "specialDefense" : 23,
          "speed" : 30
        },
        "level" : 5,
        "moves" : [

        ],
        "seed" : 14
      },
      "rarity" : "uncommon"
    }
  ],
  "dexCompletionsSeeded" : true,
  "economyVersion" : 3,
  "eggUsage" : 1200,
  "expShareHolders" : [
    "grad-1"
  ],
  "expShareTakenOff" : [
    "stored-1"
  ],
  "friendEntryIDs" : [
    "grad-2"
  ],
  "graduateEvolution" : {
    "grad-1" : {
      "candies" : 0,
      "flipped" : false,
      "graduateXP" : 0,
      "lost" : 0,
      "pets" : 0,
      "played" : 0,
      "rained" : false,
      "seenBattles" : [

      ],
      "spentBaseline" : 20000000,
      "spun" : false,
      "won" : 0
    }
  },
  "growthMode" : "time",
  "gymBadges" : {
    "regions" : {
      "kanto" : {
        "gyms" : [
          1
        ],
        "hallOfFame" : true,
        "hiddenBeaten" : false,
        "orgBeaten" : false
      }
    }
  },
  "heldItems" : {
    "grad-1" : "leftovers"
  },
  "idleHintDismissed" : true,
  "installBaselineSet" : true,
  "inventory" : {
    "mint" : 1,
    "rareCandy" : 3
  },
  "keepWaiting" : {
    "grad-1" : 6
  },
  "language" : "ko",
  "lastDate" : "2023-11-14",
  "lastUsageAt" : 721692800,
  "leftoverEvolutionItemsReturned" : true,
  "notifiedDexCompletions" : [
    "kanto"
  ],
  "parkedSpentTokens" : 20000000,
  "raisedEntryID" : "grad-1",
  "remoteOpResults" : [
    {
      "id" : 41,
      "reason" : "no_tokens"
    }
  ],
  "remoteOpsEpoch" : "epoch-1",
  "remoteOpsLastID" : 42,
  "representativeForm" : "c",
  "representativeSpeciesID" : 201,
  "rewardedDexRegions" : [
    "kanto"
  ],
  "scoutDraws" : {
    "kanto" : [
      1,
      4,
      7
    ]
  },
  "scoutedEgg" : false,
  "shinyEgg" : false,
  "spentTokens" : 30000000,
  "storedLines" : {
    "stored-1" : {
      "mon" : {
        "baseID" : 1,
        "dittoRevealed" : false,
        "evolution" : {
          "candies" : 0,
          "flipped" : false,
          "graduateXP" : 0,
          "lost" : 0,
          "pets" : 0,
          "played" : 0,
          "rained" : false,
          "seenBattles" : [

          ],
          "spentBaseline" : 0,
          "spun" : false,
          "won" : 0
        },
        "hasGrowthBoost" : false,
        "isShiny" : false,
        "nature" : "calm",
        "pathIDs" : [
          1
        ],
        "plannedPathIDs" : [
          1
        ],
        "profile" : {
          "abilityIsHidden" : false,
          "growthTokens" : 0,
          "instanceID" : "stored-1",
          "ivs" : {
            "attack" : 17,
            "defense" : 8,
            "hp" : 31,
            "specialAttack" : 19,
            "specialDefense" : 3,
            "speed" : 4
          },
          "level" : 5,
          "moves" : [

          ],
          "seed" : 13
        },
        "rarity" : "common",
        "stageIndex" : 0,
        "totalForms" : 3,
        "usedAtStage" : 50
      },
      "spentAtStore" : 10000000
    }
  },
  "stuckWatch" : {
    "id" : "grad-1",
    "since" : 721692800
  },
  "timeCredit" : 5000000,
  "tokenModeSince" : 721692800,
  "urshifuStylesRepaired" : true,
  "usedSinceInstall" : 900000000
}
"""#
}
