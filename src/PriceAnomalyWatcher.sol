// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RitualBase, IScheduler} from "./lib/RitualBase.sol";

/// @notice Polls a price source on a schedule and has the model flag anomalies
///         (scraping errors, obvious manipulation) before the value is trusted downstream.
contract PriceAnomalyWatcher is RitualBase {
    struct PricePoint {
        string rawText;
        uint16 status;
        uint256 timestamp;
    }

    struct AnomalyCheck {
        string assessment;
        bool anomalous;
        bool hasError;
        uint256 timestamp;
    }

    PricePoint[] public prices;
    AnomalyCheck[] public checks;

    uint256 public fetchScheduleId;
    uint256 public checkScheduleId;

    string public assetLabel;
    string public priceSourceUrl;

    event PriceFetched(uint256 indexed id, uint16 status);
    event AnomalyChecked(uint256 indexed id, bool anomalous);

    string constant SYSTEM_PROMPT =
        "You are a price-feed sanity checker. You will receive raw text pulled live from a "
        "price API for a given asset, along with the two prior fetches for comparison. Decide "
        "if the latest value looks like a clear scraping error or manipulation attempt (e.g. "
        "an implausible jump, a zero/null value, or malformed data), versus normal market "
        "movement. On the final line write exactly 'ANOMALY: YES' or 'ANOMALY: NO'.";

    modifier onlyScheduler() {
        require(msg.sender == SCHEDULER, "only scheduler");
        _;
    }

    function configure(string calldata _assetLabel, string calldata _priceSourceUrl) external onlyOwner {
        assetLabel = _assetLabel;
        priceSourceUrl = _priceSourceUrl;
    }

    /// @param executor call pickHTTPExecutor() first and pass the result here.
    function startFetching(address executor, uint32 frequency, uint32 numCalls, uint32 gasLimit, uint256 maxFeePerGas)
        external
        onlyOwner
        returns (uint256)
    {
        bytes memory data = abi.encodeWithSelector(this.scheduledFetch.selector, uint256(0), executor);
        fetchScheduleId = IScheduler(SCHEDULER).schedule(
            data, gasLimit, uint32(block.number) + frequency, numCalls, frequency, 100, maxFeePerGas, 0, 0, address(this)
        );
        return fetchScheduleId;
    }

    function scheduledFetch(uint256, address executor) external onlyScheduler {
        HTTPResponse memory resp = _callHTTPGet(executor, priceSourceUrl, 100);
        uint256 id = prices.length;
        prices.push(PricePoint({rawText: string(resp.body), status: resp.status, timestamp: block.timestamp}));
        emit PriceFetched(id, resp.status);
    }

    /// @param executor call pickLLMExecutor() first and pass the result here.
    function startChecking(address executor, uint32 frequency, uint32 numCalls, uint32 gasLimit, uint256 maxFeePerGas)
        external
        onlyOwner
        returns (uint256)
    {
        bytes memory data = abi.encodeWithSelector(this.scheduledCheck.selector, uint256(0), executor);
        checkScheduleId = IScheduler(SCHEDULER).schedule(
            data, gasLimit, uint32(block.number) + frequency, numCalls, frequency, 300, maxFeePerGas, 0, 0, address(this)
        );
        return checkScheduleId;
    }

    function scheduledCheck(uint256, address executor) external onlyScheduler {
        require(prices.length > 0, "no price fetched yet");

        string memory prompt = string.concat("Asset: ", assetLabel, "\nLatest fetch:\n", prices[prices.length - 1].rawText);
        if (prices.length >= 2) {
            prompt = string.concat(prompt, "\nPrior fetch:\n", prices[prices.length - 2].rawText);
        }
        if (prices.length >= 3) {
            prompt = string.concat(prompt, "\nTwo fetches ago:\n", prices[prices.length - 3].rawText);
        }

        (bool hasError, string memory content, ) = _callLLM(executor, SYSTEM_PROMPT, prompt, 300, 4096);
        bool anomalous = _containsAnomalyYes(content);

        uint256 id = checks.length;
        checks.push(AnomalyCheck({assessment: content, anomalous: anomalous, hasError: hasError, timestamp: block.timestamp}));
        emit AnomalyChecked(id, anomalous);
    }

    function _containsAnomalyYes(string memory s) internal pure returns (bool) {
        bytes memory b = bytes(s);
        bytes memory needle = bytes("ANOMALY: YES");
        if (b.length < needle.length) return false;
        for (uint256 i = 0; i <= b.length - needle.length; i++) {
            bool m = true;
            for (uint256 j = 0; j < needle.length; j++) {
                if (b[i + j] != needle[j]) {
                    m = false;
                    break;
                }
            }
            if (m) return true;
        }
        return false;
    }

    function cancelFetching() external onlyOwner {
        IScheduler(SCHEDULER).cancel(fetchScheduleId);
    }

    function cancelChecking() external onlyOwner {
        IScheduler(SCHEDULER).cancel(checkScheduleId);
    }

    function latestPrice() external view returns (PricePoint memory) {
        return prices[prices.length - 1];
    }

    function latestCheck() external view returns (AnomalyCheck memory) {
        return checks[checks.length - 1];
    }
}
