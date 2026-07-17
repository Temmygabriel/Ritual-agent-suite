// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RitualBase} from "./lib/RitualBase.sol";

contract WeatherTriggeredPayout is RitualBase {
    string public weatherUrl;
    address payable public beneficiary;
    int256 public thresholdValue;   // e.g. rainfall in mm x100, temp in Celsius x100
    bool public thresholdIsMinimum; // true = pay out if reading >= threshold, false = if <= threshold
    bool public triggered;

    bytes public lastRawBody;
    int256 public lastDeclaredValue;

    event WeatherChecked(int256 declaredValue, bytes rawBody);
    event PayoutTriggered(int256 declaredValue, uint256 amountSent);

    constructor(
        string memory _weatherUrl,
        address payable _beneficiary,
        int256 _thresholdValue,
        bool _thresholdIsMinimum
    ) {
        weatherUrl = _weatherUrl;
        beneficiary = _beneficiary;
        thresholdValue = _thresholdValue;
        thresholdIsMinimum = _thresholdIsMinimum;
    }

    /// @param declaredValue the reading you extracted from the fetched body (e.g. rainfall mm x100),
    /// submitted as evidence-backed input alongside the raw HTTP response stored for anyone to verify.
    function checkAndPayout(address executor, int256 declaredValue) external onlyOwner {
        require(!triggered, "Already triggered");

        HTTPResponse memory resp = _callHTTPGet(executor, weatherUrl, 60);
        require(resp.status == 200, "HTTP fetch failed");

        lastRawBody = resp.body;
        lastDeclaredValue = declaredValue;
        emit WeatherChecked(declaredValue, resp.body);

        bool conditionMet = thresholdIsMinimum
            ? declaredValue >= thresholdValue
            : declaredValue <= thresholdValue;

        if (conditionMet) {
            triggered = true;
            uint256 amount = address(this).balance;
            (bool ok, ) = beneficiary.call{value: amount}("");
            require(ok, "Payout transfer failed");
            emit PayoutTriggered(declaredValue, amount);
        }
    }

    function fundPayout() external payable onlyOwner {}
}
