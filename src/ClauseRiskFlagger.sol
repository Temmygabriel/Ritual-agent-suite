// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RitualBase} from "./lib/RitualBase.sol";

/// @notice Paste a clause from a lease, loan, or contract; get a plain-English risk read.
/// @dev Use case: consumer protection. Anyone can check a clause before signing.
contract ClauseRiskFlagger is RitualBase {
    struct Analysis {
        address requester;
        string clauseText;
        string riskAssessment;
        bool hasError;
        uint256 timestamp;
    }

    Analysis[] public analyses;

    event ClauseAnalyzed(uint256 indexed id, address indexed requester);

    string constant SYSTEM_PROMPT =
        "You are a consumer-protection assistant. Given a single clause from a lease, "
        "loan, or contract, identify whether it is unusually risky or predatory for the "
        "signer (e.g. hidden fees, one-sided termination rights, unusual liability shifts, "
        "auto-renewal traps, waived legal rights). Answer in 3-5 plain sentences, in plain "
        "language a non-lawyer can understand. If the clause looks standard and fair, say so.";

    /// @param executor call pickLLMExecutor() first (free, view) and pass the result here.
    function analyzeClause(address executor, string calldata clauseText) external returns (uint256 id) {
        string memory content = _callLLMSimple(executor, SYSTEM_PROMPT, clauseText, 300, 4096);

        id = analyses.length;
        analyses.push(Analysis({
            requester: msg.sender,
            clauseText: clauseText,
            riskAssessment: content,
            hasError: false,
            timestamp: block.timestamp
        }));

        emit ClauseAnalyzed(id, msg.sender);
    }

    function getAnalysis(uint256 id) external view returns (Analysis memory) {
        return analyses[id];
    }

    function totalAnalyses() external view returns (uint256) {
        return analyses.length;
    }
}
