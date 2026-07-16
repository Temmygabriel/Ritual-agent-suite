// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RitualBase} from "./lib/RitualBase.sol";

/// @notice Screens submitted text before it's posted to a DAO/forum, with an on-chain,
///         TEE-attested record that the check actually ran.
contract ContentModerator is RitualBase {
    struct Submission {
        address submitter;
        string content;
        bool approved;
        string reason;
        bool hasError;
        uint256 timestamp;
    }

    Submission[] public submissions;

    event ContentModerated(uint256 indexed id, address indexed submitter, bool approved);

    string constant SYSTEM_PROMPT =
        "You are a content moderator for a community forum. Given a submitted post, decide "
        "if it should be APPROVED or REJECTED. Reject only for: harassment/hate speech, "
        "explicit spam/scam links, doxxing, or graphic violent content. Respond with exactly "
        "one line starting with 'APPROVED:' or 'REJECTED:' followed by a one-sentence reason.";

    function submitForModeration(address executor, string calldata content) external returns (uint256 id) {
        (bool hasError, string memory result, ) = _callLLM(executor, SYSTEM_PROMPT, content, 300, 4096);

        bool approved = _startsWithApproved(result);

        id = submissions.length;
        submissions.push(Submission({
            submitter: msg.sender,
            content: content,
            approved: approved,
            reason: result,
            hasError: hasError,
            timestamp: block.timestamp
        }));

        emit ContentModerated(id, msg.sender, approved);
    }

    function _startsWithApproved(string memory s) internal pure returns (bool) {
        bytes memory b = bytes(s);
        bytes memory prefix = bytes("APPROVED");
        if (b.length < prefix.length) return false;
        for (uint256 i = 0; i < prefix.length; i++) {
            if (b[i] != prefix[i]) return false;
        }
        return true;
    }

    function getSubmission(uint256 id) external view returns (Submission memory) {
        return submissions[id];
    }

    function totalSubmissions() external view returns (uint256) {
        return submissions.length;
    }
}
