// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ITEEServiceRegistry {
    function getServicesByCapability(uint8 capability) external view returns (address[] memory);
    function pickServiceByCapability(uint8 capability) external view returns (address);
}

interface IRitualWallet {
    function deposit(address contractAddr, uint256 lockDuration) external payable;
    function withdraw(address contractAddr, uint256 amount) external;
    function balanceOf(address contractAddr) external view returns (uint256);
    function lockUntil(address contractAddr) external view returns (uint256);
}

interface IScheduler {
    function schedule(
        bytes calldata callData,
        uint32 gasLimit,
        uint32 startBlock,
        uint32 numCalls,
        uint32 frequency,
        uint32 ttl,
        uint256 maxFeePerGas,
        uint256 minStake,
        uint256 penaltyAmount,
        address target
    ) external returns (uint256 jobId);
    function cancel(uint256 jobId) external;
}

contract RitualBase {
    address internal constant RITUAL_WALLET       = 0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948;
    address internal constant TEE_SERVICE_REGISTRY = 0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F;
    address internal constant SCHEDULER           = 0x56e776BAE2DD60664b69Bd5F865F1180ffB7D58B;
    address internal constant HTTP_PRECOMPILE     = 0x0000000000000000000000000000000000000801;
    address internal constant LLM_PRECOMPILE      = 0x0000000000000000000000000000000000000802;

    uint8 internal constant CAP_HTTP_CALL = 0;
    uint8 internal constant CAP_LLM       = 1;

    string internal constant LLM_MODEL = "zai-org/GLM-4.7-FP8";

    address public owner;
    modifier onlyOwner() { require(msg.sender == owner, "Not owner"); _; }
    constructor() { owner = msg.sender; }

    struct ConvoRef { string platform; string path; string keyRef; }

    struct HTTPResponse {
        uint16   status;
        string[] headerKeys;
        string[] headerValues;
        bytes    body;
        string   errorMessage;
    }

    receive() external payable {}

    function depositForFees(uint256 lockDuration) external payable onlyOwner {
        IRitualWallet(RITUAL_WALLET).deposit{value: msg.value}(address(this), lockDuration);
    }

    function withdrawFromRitualWallet(uint256 amount) external onlyOwner {
        IRitualWallet(RITUAL_WALLET).withdraw(address(this), amount);
    }

    function withdrawToOwner(uint256 amount) external onlyOwner {
        (bool ok,) = owner.call{value: amount}("");
        require(ok, "Transfer failed");
    }

    function ritualWalletStatus() external view returns (uint256 balance, uint256 lockUntilBlock) {
        balance        = IRitualWallet(RITUAL_WALLET).balanceOf(address(this));
        lockUntilBlock = IRitualWallet(RITUAL_WALLET).lockUntil(address(this));
    }

    function pickLLMExecutor() public view returns (address) {
        try ITEEServiceRegistry(TEE_SERVICE_REGISTRY).pickServiceByCapability(CAP_LLM)
            returns (address a) { if (a != address(0)) return a; } catch {}
        address[] memory list = ITEEServiceRegistry(TEE_SERVICE_REGISTRY)
            .getServicesByCapability(CAP_LLM);
        require(list.length > 0, "No LLM executor");
        return list[0];
    }

    function pickHTTPExecutor() public view returns (address) {
        try ITEEServiceRegistry(TEE_SERVICE_REGISTRY).pickServiceByCapability(CAP_HTTP_CALL)
            returns (address a) { if (a != address(0)) return a; } catch {}
        address[] memory list = ITEEServiceRegistry(TEE_SERVICE_REGISTRY)
            .getServicesByCapability(CAP_HTTP_CALL);
        require(list.length > 0, "No HTTP executor");
        return list[0];
    }

    function _jsonEscape(string memory input) internal pure returns (string memory) {
        bytes memory b = bytes(input);
        bytes memory out = new bytes(b.length * 2);
        uint256 j;
        for (uint256 i; i < b.length; i++) {
            bytes1 c = b[i];
            if      (c == 0x22) { out[j++] = '\\'; out[j++] = '"';  }
            else if (c == 0x5C) { out[j++] = '\\'; out[j++] = '\\'; }
            else if (c < 0x20)  { out[j++] = '\\'; out[j++] = 'n';  }
            else                 { out[j++] = c; }
        }
        bytes memory trimmed = new bytes(j);
        for (uint256 k; k < j; k++) trimmed[k] = out[k];
        return string(trimmed);
    }

    function _callLLM(
        address executor,
        string memory systemPrompt,
        string memory userPrompt,
        uint256 ttl,
        uint32  maxCompletionTokens
    ) internal returns (bool hasError, string memory content, string memory errMsg) {
        ConvoRef memory emptyConvo = ConvoRef("", "", "");

        string memory messagesJson = string(abi.encodePacked(
            '[{"role":"system","content":"', _jsonEscape(systemPrompt),
            '"},{"role":"user","content":"',  _jsonEscape(userPrompt), '"}]'
        ));

        bytes memory payload = abi.encode(
            executor,
            LLM_MODEL,
            messagesJson,
            uint32(0),
            uint32(0),
            false,
            uint8(0),
            maxCompletionTokens,
            uint32(1),
            uint32(0),
            "",
            uint32(0),
            "",
            false,
            uint32(100),
            uint32(100),
            "",
            "",
            false,
            "",
            ttl,
            uint256(0),
            "",
            uint256(0),
            uint256(0),
            "",
            uint256(0),
            uint256(0),
            "",
            emptyConvo
        );

        (bool ok, bytes memory raw) = LLM_PRECOMPILE.call(payload);
        if (!ok) { return (true, "", "LLM precompile call failed"); }

        (hasError, , errMsg) = abi.decode(raw, (bool, bytes, string));
        if (hasError) { return (true, "", errMsg); }

        (, bytes memory completionData, ) = abi.decode(raw, (bool, bytes, string));
        (, bytes[] memory choicesData)    = abi.decode(completionData, (string, bytes[]));
        (, bytes memory messageData)      = abi.decode(choicesData[0], (uint256, bytes));
        (, content)                       = abi.decode(messageData, (string, string));
    }

    function _callHTTPGet(
        address executor,
        string memory url,
        uint256 ttl
    ) internal returns (HTTPResponse memory resp) {
        bytes memory payload = abi.encode(
            executor,
            url,
            "GET",
            new string[](0),
            new string[](0),
            "",
            ttl,
            uint256(0),
            "",
            uint256(0),
            uint256(0),
            "",
            uint256(0)
        );

        (bool ok, bytes memory raw) = HTTP_PRECOMPILE.call(payload);
        require(ok, "HTTP precompile call failed");
        resp = abi.decode(raw, (HTTPResponse));
    }

    function _callLLMSimple(
        address executor,
        string memory systemPrompt,
        string memory userPrompt,
        uint256 ttl,
        uint32 maxCompletionTokens
    ) internal returns (string memory content) {
        (, content, ) = _callLLM(executor, systemPrompt, userPrompt, ttl, maxCompletionTokens);
    }
}