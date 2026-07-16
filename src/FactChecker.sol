// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RitualBase} from "./lib/RitualBase.sol";

/// @notice Fetches a live source, then has the model weigh it against a claim.
/// @dev Only one async precompile call is allowed per transaction, so this is a
///      two-step flow: (1) fetchSource() pulls a URL and stores the text on-chain,
///      (2) checkClaim() runs the LLM judgment using previously fetched sources as
///      context. Call fetchSource for each source URL first, then checkClaim.
contract FactChecker is RitualBase {
    struct Source {
        string url;
        string body;
        uint16 status;
        uint256 timestamp;
    }

    struct Verdict {
        address requester;
        string claim;
        uint256[] sourceIds;
        string verdict;
        bool hasError;
        uint256 timestamp;
    }

    Source[] public sources;
    Verdict[] public verdicts;

    event SourceFetched(uint256 indexed id, string url, uint16 status);
    event ClaimChecked(uint256 indexed id, address indexed requester);

    string constant SYSTEM_PROMPT =
        "You are a fact-checking assistant. You will receive a claim and one or more source "
        "excerpts pulled live from the web, separated by '---SOURCE---'. Weigh the evidence "
        "and respond with: a verdict (Supported / Contradicted / Unclear / Insufficient "
        "Evidence), then 2-3 sentences explaining why, citing which source supports your "
        "reasoning. Do not use outside knowledge beyond what's in the sources.";

    /// @param executor call pickHTTPExecutor() first and pass the result here.
    function fetchSource(address executor, string calldata url) external returns (uint256 id) {
        HTTPResponse memory resp = _callHTTPGet(executor, url, 100);

        id = sources.length;
        sources.push(Source({
            url: url,
            body: string(resp.body),
            status: resp.status,
            timestamp: block.timestamp
        }));

        emit SourceFetched(id, url, resp.status);
    }

    /// @param executor call pickLLMExecutor() first and pass the result here.
    /// @param sourceIds ids returned by prior fetchSource() calls to use as evidence.
    function checkClaim(address executor, string calldata claim, uint256[] calldata sourceIds)
        external
        returns (uint256 id)
    {
        string memory combined = claim;
        for (uint256 i = 0; i < sourceIds.length; i++) {
            combined = string.concat(combined, "\n---SOURCE---\n", sources[sourceIds[i]].body);
        }

        (bool hasError, string memory content, ) = _callLLM(executor, SYSTEM_PROMPT, combined, 300, 4096);

        id = verdicts.length;
        verdicts.push(Verdict({
            requester: msg.sender,
            claim: claim,
            sourceIds: sourceIds,
            verdict: content,
            hasError: hasError,
            timestamp: block.timestamp
        }));

        emit ClaimChecked(id, msg.sender);
    }

    function getSource(uint256 id) external view returns (Source memory) {
        return sources[id];
    }

    function getVerdict(uint256 id) external view returns (Verdict memory) {
        return verdicts[id];
    }
}
