// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RitualBase, IRitualWallet} from "./lib/RitualBase.sol";

/// @notice Anyone can pay a small RITUAL fee to ask a question and get one AI answer.
///         An ownerless, metered API -- no subscription, no centralized backend.
contract PayPerQuestionExpert is RitualBase {
    struct QA {
        address asker;
        string question;
        string answer;
        bool hasError;
        uint256 paid;
        uint256 timestamp;
    }

    QA[] public history;

    /// @notice Price per question, in wei. Owner can adjust as testnet economics change.
    uint256 public pricePerQuestion = 0.01 ether;

    event PriceUpdated(uint256 newPrice);
    event QuestionAsked(uint256 indexed id, address indexed asker, uint256 paid);

    string constant SYSTEM_PROMPT =
        "You are a knowledgeable general-purpose expert assistant. Answer the user's question "
        "clearly and concisely in 3-6 sentences. If the question is ambiguous, state your "
        "assumption and answer anyway.";

    /// @param executor call pickLLMExecutor() first and pass the result here.
    /// @dev Caller must send at least `pricePerQuestion` in msg.value. The payment is used to
    ///      fund this contract's own RitualWallet balance (which pays the LLM precompile fee).
    function askQuestion(address executor, string calldata question) external payable returns (uint256 id) {
        require(msg.value >= pricePerQuestion, "insufficient payment");

        // Fund this contract's own RitualWallet balance with the payment so the
        // precompile fee for THIS call is covered before we submit it.
        IRitualWallet(RITUAL_WALLET).deposit{value: msg.value}(address(this), 5000);

        (bool hasError, string memory answer, ) = _callLLM(executor, SYSTEM_PROMPT, question, 300, 4096);

        id = history.length;
        history.push(QA({
            asker: msg.sender,
            question: question,
            answer: answer,
            hasError: hasError,
            paid: msg.value,
            timestamp: block.timestamp
        }));

        emit QuestionAsked(id, msg.sender, msg.value);
    }

    function setPrice(uint256 newPrice) external onlyOwner {
        pricePerQuestion = newPrice;
        emit PriceUpdated(newPrice);
    }

    function getQA(uint256 id) external view returns (QA memory) {
        return history[id];
    }

    function totalQuestions() external view returns (uint256) {
        return history.length;
    }
}
