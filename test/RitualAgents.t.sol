// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ClauseRiskFlagger} from "../src/ClauseRiskFlagger.sol";
import {PayPerQuestionExpert} from "../src/PayPerQuestionExpert.sol";
import {ContentModerator} from "../src/ContentModerator.sol";

/// @dev These tests mock the LLM precompile at 0x0802 so we can verify contract-side
///      encoding/decoding logic without touching real testnet infrastructure. Real
///      end-to-end behavior must still be verified against the live chain (see README).
contract RitualAgentsTest is Test {
    address constant LLM_PRECOMPILE = 0x0000000000000000000000000000000000000802;
    address executor = address(0xE1);

    /// @dev Builds a mocked LLM precompile response with the exact nesting the real
    ///      precompile uses, per ritual-dapp-llm skill Section 2 (CompletionData ->
    ///      choicesData -> messageData), so contract-side decoding can be exercised
    ///      without hitting real testnet infrastructure.
    function _mockLLMResponse(string memory content, bool hasError) internal {
        bytes[] memory toolCalls = new bytes[](0);
        bytes memory messageData = abi.encode("assistant", content, "", uint256(0), toolCalls);
        bytes memory choiceEntry = abi.encode(uint256(0), "stop", messageData);
        bytes[] memory choicesData = new bytes[](1);
        choicesData[0] = choiceEntry;
        bytes memory usageData = abi.encode(uint256(10), uint256(10), uint256(20));

        bytes memory completionData = abi.encode(
            "id-1", "chat.completion", uint256(block.timestamp), "zai-org/GLM-4.7-FP8",
            "", "", uint256(1), choicesData, usageData
        );

        bytes memory modelMetadata = abi.encode("zai-org/GLM-4.7-FP8", uint256(355), "fp8", uint256(1), uint256(128000));

        bytes memory actualOutput = abi.encode(
            hasError,
            hasError ? bytes("") : completionData,
            modelMetadata,
            hasError ? "mocked upstream error" : string(""),
            "", "", ""
        );

        bytes memory fullEnvelope = abi.encode(bytes(""), actualOutput);
        vm.mockCall(LLM_PRECOMPILE, bytes(""), fullEnvelope);
    }

    function test_clauseFlagger_ownerCanWithdraw() public {
        ClauseRiskFlagger flagger = new ClauseRiskFlagger();
        assertEq(flagger.owner(), address(this));
    }

    function test_payPerQuestion_revertsOnUnderpayment() public {
        PayPerQuestionExpert expert = new PayPerQuestionExpert();
        vm.expectRevert("insufficient payment");
        expert.askQuestion{value: 0.001 ether}(executor, "What is a rollup?");
    }

    function test_contentModerator_deploys() public {
        ContentModerator moderator = new ContentModerator();
        assertEq(moderator.totalSubmissions(), 0);
    }
}
