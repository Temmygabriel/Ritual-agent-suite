// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RitualBase} from "./lib/RitualBase.sol";

contract PriceFeedSanityChecker is RitualBase {
    string public priceUrl;
    uint256 public lastPriceCents;
    bytes public lastRawBody;
    uint256 public lastCheckBlock;
    uint256 public anomalyThresholdBps; // e.g. 2000 = 20%

    event PriceChecked(uint256 priceCents, bytes rawBody);
    event AnomalyFlagged(uint256 oldPriceCents, uint256 newPriceCents, uint256 changeBps);

    constructor(string memory _priceUrl, uint256 _anomalyThresholdBps) {
        priceUrl = _priceUrl;
        anomalyThresholdBps = _anomalyThresholdBps;
    }

    /// @param declaredPriceCents the price you read off the fetched body, submitted as
    /// evidence-backed input since Solidity can't cheaply parse arbitrary JSON on-chain.
    function checkPrice(address executor, uint256 declaredPriceCents) external onlyOwner {
        HTTPResponse memory resp = _callHTTPGet(executor, priceUrl, 60);
        require(resp.status == 200, "HTTP fetch failed");

        lastRawBody = resp.body;
        lastCheckBlock = block.number;

        if (lastPriceCents > 0) {
            uint256 diff = declaredPriceCents > lastPriceCents
                ? declaredPriceCents - lastPriceCents
                : lastPriceCents - declaredPriceCents;
            uint256 changeBps = (diff * 10000) / lastPriceCents;
            if (changeBps > anomalyThresholdBps) {
                emit AnomalyFlagged(lastPriceCents, declaredPriceCents, changeBps);
            }
        }

        lastPriceCents = declaredPriceCents;
        emit PriceChecked(declaredPriceCents, resp.body);
    }
}
