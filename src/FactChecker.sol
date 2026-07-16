// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RitualBase} from "./lib/RitualBase.sol";

contract FactChecker is RitualBase {
    struct Source { string url; string content; bool fetched; }

    mapping(uint256 => Source) public sources;
    uint256 public sourceCount;

    event SourceFetched(uint256 indexed id, string url);
    event ClaimResult(string claim, string verdict);

    function fetchSource(address executor, string calldata url) external onlyOwner {
        HTTPResponse memory resp = _callHTTPGet(executor, url, 60);
        require(resp.status == 200, "HTTP fetch failed");
        sources[sourceCount] = Source(url, string(resp.body), true);
        emit SourceFetched(sourceCount, url);
        sourceCount++;
    }

    function checkClaim(
        address executor,
        string calldata claim,
        uint256[] calldata sourceIds
    ) external onlyOwner returns (string memory verdict) {
        string memory evidence = "";
        for (uint256 i; i < sourceIds.length; i++) {
            require(sources[sourceIds[i]].fetched, "Source not fetched");
            evidence = string(abi.encodePacked(evidence, sources[sourceIds[i]].content, " "));
        }
        string memory system = "You are a fact-checker. Given evidence and a claim, reply SUPPORTED, REFUTED, or INSUFFICIENT with a one-sentence reason.";
        string memory user   = string(abi.encodePacked("Evidence: ", evidence, "\nClaim: ", claim));
        verdict = _callLLMSimple(executor, system, user, 60, 200);
        emit ClaimResult(claim, verdict);
    }
}
