// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RitualBase} from "./lib/RitualBase.sol";

contract DomainUptimeMonitor is RitualBase {
    struct Check {
        uint256 blockNumber;
        uint16  statusCode;
        bool    up;
    }

    string public targetUrl;
    Check[] public history;

    uint256 public totalChecks;
    uint256 public totalUp;

    event UptimeChecked(uint256 indexed checkId, uint16 statusCode, bool up);

    constructor(string memory _targetUrl) {
        targetUrl = _targetUrl;
    }

    function ping(address executor) external onlyOwner returns (bool up) {
        HTTPResponse memory resp = _callHTTPGet(executor, targetUrl, 60);
        up = resp.status >= 200 && resp.status < 400;

        history.push(Check({
            blockNumber: block.number,
            statusCode: resp.status,
            up: up
        }));

        totalChecks++;
        if (up) totalUp++;

        emit UptimeChecked(history.length - 1, resp.status, up);
    }

    function uptimeBps() external view returns (uint256) {
        if (totalChecks == 0) return 0;
        return (totalUp * 10000) / totalChecks;
    }

    function historyLength() external view returns (uint256) {
        return history.length;
    }
}
