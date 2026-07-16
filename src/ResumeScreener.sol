// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RitualBase} from "./lib/RitualBase.sol";

/// @notice Scores a resume against a job spec and explains its reasoning on-chain.
/// @dev Explicitly instructed to ignore protected-class signals and to flag when it
///      can't assess fairly, rather than silently guessing.
contract ResumeScreener is RitualBase {
    struct Screening {
        address submitter;
        string jobSpec;
        string resumeText;
        string result;
        bool hasError;
        uint256 timestamp;
    }

    Screening[] public screenings;

    event ResumeScreened(uint256 indexed id, address indexed submitter);

    string constant SYSTEM_PROMPT =
        "You are a resume screening assistant. You will be given a job specification and a "
        "resume, separated by '---RESUME---'. Score the fit from 0-100 and explain the top 3 "
        "reasons for the score, referencing only job-relevant skills and experience. Do not "
        "consider or mention age, gender, race, name origin, marital/family status, "
        "disability, or any other protected characteristic -- if the resume text makes such "
        "an assessment impossible to avoid, say so explicitly instead of scoring. Format: "
        "'Score: X/100' on the first line, reasons after.";

    function screenResume(address executor, string calldata jobSpec, string calldata resumeText)
        external
        returns (uint256 id)
    {
        string memory combined = string.concat(jobSpec, "\n---RESUME---\n", resumeText);
        string memory content = _callLLMSimple(executor, SYSTEM_PROMPT, combined, 300, 4096);

        id = screenings.length;
        screenings.push(Screening({
            submitter: msg.sender,
            jobSpec: jobSpec,
            resumeText: resumeText,
            result: content,
            hasError: false,
            timestamp: block.timestamp
        }));

        emit ResumeScreened(id, msg.sender);
    }

    function getScreening(uint256 id) external view returns (Screening memory) {
        return screenings[id];
    }

    function totalScreenings() external view returns (uint256) {
        return screenings.length;
    }
}
