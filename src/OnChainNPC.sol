// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RitualBase} from "./lib/RitualBase.sol";

/// @notice A game NPC that remembers each player's conversation because the history
///         genuinely lives in contract storage on-chain -- not a game server's database.
/// @dev Keeps history simple (plain contract storage, not the LLM precompile's DA/StorageRef
///      feature) so there's no external GCS/HuggingFace/Pinata credential setup required.
///      Each turn re-sends recent history as part of the prompt.
contract OnChainNPC is RitualBase {
    struct Turn {
        string speaker; // "player" or "npc"
        string text;
        uint256 timestamp;
    }

    mapping(address => Turn[]) public conversations;

    /// @notice How many prior turns (player+npc combined) to replay as context each call.
    uint256 public memoryWindow = 6;

    string public npcPersona =
        "You are Old Man Ferris, a gruff but kind-hearted lighthouse keeper NPC in a fantasy "
        "game. Speak in character, in 2-4 sentences per reply. Remember what the player has "
        "told you earlier in this conversation and refer back to it naturally.";

    event NPCReplied(address indexed player, uint256 turnIndex, bool hasError);

    function setPersona(string calldata persona) external onlyOwner {
        npcPersona = persona;
    }

    function setMemoryWindow(uint256 turns) external onlyOwner {
        memoryWindow = turns;
    }

    /// @param executor call pickLLMExecutor() first and pass the result here.
    function talk(address executor, string calldata message) external returns (string memory reply) {
        Turn[] storage history = conversations[msg.sender];

        string memory context = "";
        uint256 len = history.length;
        uint256 start = len > memoryWindow ? len - memoryWindow : 0;
        for (uint256 i = start; i < len; i++) {
            context = string.concat(context, history[i].speaker, ": ", history[i].text, "\n");
        }

        string memory prompt = bytes(context).length > 0
            ? string.concat("Conversation so far:\n", context, "player: ", message)
            : string.concat("player: ", message);

        string memory content = _callLLMSimple(executor, npcPersona, prompt, 300, 4096);

        history.push(Turn({speaker: "player", text: message, timestamp: block.timestamp}));
        history.push(Turn({speaker: "npc", text: content, timestamp: block.timestamp}));

        emit NPCReplied(msg.sender, history.length - 1, false);
        reply = content;
    }

    function conversationLength(address player) external view returns (uint256) {
        return conversations[player].length;
    }

    function getTurn(address player, uint256 index) external view returns (Turn memory) {
        return conversations[player][index];
    }
}
