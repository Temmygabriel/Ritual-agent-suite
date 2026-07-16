// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RitualBase} from "./lib/RitualBase.sol";

/// @notice Submit insurance claim details; get a priority/plausibility score for a human reviewer.
/// @dev This does NOT approve or deny claims — it's a triage aid, output is advisory only.
contract ClaimTriageAssistant is RitualBase {
    struct Claim {
        address submitter;
        string details;
        string triageNotes;
        bool hasError;
        uint256 timestamp;
        bool reviewed;
    }

    Claim[] public claims;

    event ClaimSubmitted(uint256 indexed id, address indexed submitter);
    event ClaimReviewed(uint256 indexed id, address indexed reviewer);

    string constant SYSTEM_PROMPT =
        "You are an insurance claim triage assistant for a human adjuster. Given claim "
        "details, produce: (1) a priority level (Low/Medium/High/Urgent), (2) any red flags "
        "suggesting possible fraud or missing information, (3) what documentation the adjuster "
        "should request next. Be concise. You are advisory only -- never state a claim is "
        "approved, denied, or paid.";

    function submitClaim(address executor, string calldata details) external returns (uint256 id) {
        string memory content = _callLLMSimple(executor, SYSTEM_PROMPT, details, 300, 4096);

        id = claims.length;
        claims.push(Claim({
            submitter: msg.sender,
            details: details,
            triageNotes: content,
            hasError: false,
            timestamp: block.timestamp,
            reviewed: false
        }));

        emit ClaimSubmitted(id, msg.sender);
    }

    /// @notice Owner (the adjuster/operator) marks a claim as reviewed once handled off-chain.
    function markReviewed(uint256 id) external onlyOwner {
        claims[id].reviewed = true;
        emit ClaimReviewed(id, msg.sender);
    }

    function getClaim(uint256 id) external view returns (Claim memory) {
        return claims[id];
    }

    function totalClaims() external view returns (uint256) {
        return claims.length;
    }
}
