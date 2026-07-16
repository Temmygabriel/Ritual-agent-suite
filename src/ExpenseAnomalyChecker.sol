// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RitualBase} from "./lib/RitualBase.sol";

/// @notice Flags duplicate, inflated, or out-of-policy expense/invoice line items.
contract ExpenseAnomalyChecker is RitualBase {
    struct Review {
        address submitter;
        string policySummary;
        string lineItems;
        string findings;
        bool hasError;
        uint256 timestamp;
    }

    Review[] public reviews;

    event ExpenseReviewed(uint256 indexed id, address indexed submitter);

    string constant SYSTEM_PROMPT =
        "You are an expense-policy compliance assistant. You will receive a short company "
        "expense policy summary and a list of line items (one per line: description, amount, "
        "category), separated by '---ITEMS---'. Flag: (1) items that look duplicated, "
        "(2) amounts that look inflated for the stated category, (3) anything that appears "
        "out of policy. List findings as short bullet points. If nothing looks wrong, say so.";

    function reviewExpenses(address executor, string calldata policySummary, string calldata lineItems)
        external
        returns (uint256 id)
    {
        string memory combined = string.concat(policySummary, "\n---ITEMS---\n", lineItems);
        (bool hasError, string memory content, ) = _callLLM(executor, SYSTEM_PROMPT, combined, 300, 4096);

        id = reviews.length;
        reviews.push(Review({
            submitter: msg.sender,
            policySummary: policySummary,
            lineItems: lineItems,
            findings: content,
            hasError: hasError,
            timestamp: block.timestamp
        }));

        emit ExpenseReviewed(id, msg.sender);
    }

    function getReview(uint256 id) external view returns (Review memory) {
        return reviews[id];
    }

    function totalReviews() external view returns (uint256) {
        return reviews.length;
    }
}
