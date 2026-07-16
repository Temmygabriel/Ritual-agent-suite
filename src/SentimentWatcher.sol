// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RitualBase, IScheduler} from "./lib/RitualBase.sol";

/// @notice Watches a topic on a schedule, summarizes sentiment shifts, flags spikes.
/// @dev "Persistent" behavior here is achieved via the Scheduler contract calling this
///      contract back on a fixed cadence -- it keeps running after you close the tab,
///      without needing the full Sovereign/Persistent Agent precompiles.
contract SentimentWatcher is RitualBase {
    struct Snapshot {
        string rawText;
        uint16 status;
        uint256 timestamp;
    }

    struct SentimentReport {
        string summary;
        bool flagged;
        bool hasError;
        uint256 timestamp;
    }

    Snapshot[] public snapshots;
    SentimentReport[] public reports;

    uint256 public fetchScheduleId;
    uint256 public analyzeScheduleId;

    string public topic;
    string public sourceUrl;

    event SnapshotFetched(uint256 indexed id, uint16 status);
    event SentimentAnalyzed(uint256 indexed id, bool flagged);

    string constant SYSTEM_PROMPT =
        "You are a brand/topic sentiment monitor. You will receive raw text pulled live from "
        "the web about a topic, plus the topic name. Summarize the current sentiment in 2-3 "
        "sentences. On the final line, write exactly 'FLAG: YES' if there is a sudden negative "
        "shift, coordinated pile-on, or crisis-level language, otherwise write 'FLAG: NO'.";

    modifier onlyScheduler() {
        require(msg.sender == SCHEDULER, "only scheduler");
        _;
    }

    /// @notice Set what to watch and which URL to poll for raw text (e.g. a news/search API).
    function configure(string calldata _topic, string calldata _sourceUrl) external onlyOwner {
        topic = _topic;
        sourceUrl = _sourceUrl;
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
        HTTPResponse memory resp = _callHTTPGet(executor, sourceUrl, 100);
        uint256 id = snapshots.length;
        snapshots.push(Snapshot({rawText: string(resp.body), status: resp.status, timestamp: block.timestamp}));
        emit SnapshotFetched(id, resp.status);
    }

    /// @param executor call pickLLMExecutor() first and pass the result here.
    function startAnalyzing(address executor, uint32 frequency, uint32 numCalls, uint32 gasLimit, uint256 maxFeePerGas)
        external
        onlyOwner
        returns (uint256)
    {
        bytes memory data = abi.encodeWithSelector(this.scheduledAnalyze.selector, uint256(0), executor);
        analyzeScheduleId = IScheduler(SCHEDULER).schedule(
            data, gasLimit, uint32(block.number) + frequency, numCalls, frequency, 300, maxFeePerGas, 0, 0, address(this)
        );
        return analyzeScheduleId;
    }

    function scheduledAnalyze(uint256, address executor) external onlyScheduler {
        require(snapshots.length > 0, "no snapshot yet");
        Snapshot memory latest = snapshots[snapshots.length - 1];
        string memory prompt = string.concat("Topic: ", topic, "\nRaw text:\n", latest.rawText);

        (bool hasError, string memory content, ) = _callLLM(executor, SYSTEM_PROMPT, prompt, 300, 4096);
        bool flagged = _containsFlagYes(content);

        uint256 id = reports.length;
        reports.push(SentimentReport({summary: content, flagged: flagged, hasError: hasError, timestamp: block.timestamp}));
        emit SentimentAnalyzed(id, flagged);
    }

    function _containsFlagYes(string memory s) internal pure returns (bool) {
        bytes memory b = bytes(s);
        bytes memory needle = bytes("FLAG: YES");
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

    function cancelAnalyzing() external onlyOwner {
        IScheduler(SCHEDULER).cancel(analyzeScheduleId);
    }

    function latestSnapshot() external view returns (Snapshot memory) {
        return snapshots[snapshots.length - 1];
    }

    function latestReport() external view returns (SentimentReport memory) {
        return reports[reports.length - 1];
    }
}
