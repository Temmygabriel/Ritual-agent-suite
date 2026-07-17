// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RitualBase} from "./lib/RitualBase.sol";

contract GitHubReleaseWatcher is RitualBase {
    string public repoRawUrl; // raw file host URL pointing at a version marker (e.g. raw.githubusercontent.com/OWNER/REPO/main/VERSION)
    string public latestVersion;
    bytes public lastRawBody;
    uint256 public lastCheckBlock;

    event VersionChecked(string version, bytes rawBody);
    event NewVersionDetected(string oldVersion, string newVersion);

    constructor(string memory _repoRawUrl) {
        repoRawUrl = _repoRawUrl;
    }

    /// @param declaredVersion the version string you read off the fetched body, submitted as
    /// evidence-backed input alongside the raw HTTP response stored for anyone to verify.
    function checkVersion(address executor, string calldata declaredVersion) external onlyOwner {
        HTTPResponse memory resp = _callHTTPGet(executor, repoRawUrl, 60);
        require(resp.status == 200, "HTTP fetch failed");

        lastRawBody = resp.body;
        lastCheckBlock = block.number;
        emit VersionChecked(declaredVersion, resp.body);

        if (bytes(latestVersion).length > 0 &&
            keccak256(bytes(latestVersion)) != keccak256(bytes(declaredVersion))) {
            emit NewVersionDetected(latestVersion, declaredVersion);
        }

        latestVersion = declaredVersion;
    }
}
