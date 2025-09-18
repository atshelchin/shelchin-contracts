// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IERC721 {
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
}

interface IERC1155 {
    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data) external;
}

/**
 * @title Delegator
 * @dev Execute arbitrary calls with owner authorization and support multiple asset types
 */
contract Delegator {
    address public owner;
    bool private initialized;

    struct Call {
        address to;
        bytes data;
        uint256 value;
    }

    error NotOwner();
    error InvalidTarget();
    error InvalidNewOwner();
    error InsufficientETH();
    error CallFailed(uint256 index);
    error NoBalance();
    error WithdrawFailed();
    error AlreadyInitialized();
    error NotInitialized();

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event CallExecuted(address indexed to, uint256 value, bool success);
    event BatchCallExecuted(uint256 callsCount, uint256 successCount);
    event Initialized(address indexed owner);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier initializer() {
        if (initialized) revert AlreadyInitialized();
        _;
        initialized = true;
    }

    /**
     * @dev Initialize the contract with an owner
     * @param _owner Initial owner address
     */
    function initialize(address _owner) external initializer {
        if (_owner == address(0)) revert InvalidNewOwner();
        owner = _owner;
        emit Initialized(_owner);
    }

    /**
     * @dev Execute a single call
     * @param to Target address
     * @param data Call data
     * @param value ETH value to send
     */
    function execute(address to, bytes calldata data, uint256 value)
        external
        payable
        onlyOwner
        returns (bool success, bytes memory result)
    {
        if (to == address(0)) revert InvalidTarget();
        if (msg.value < value) revert InsufficientETH();

        (success, result) = to.call{value: value}(data);

        emit CallExecuted(to, value, success);

        if (!success) {
            if (result.length > 0) {
                assembly {
                    revert(add(32, result), mload(result))
                }
            }
            revert CallFailed(0);
        }
    }

    /**
     * @dev Execute multiple calls in a single transaction
     * @param calls Array of Call structs
     */
    function executeBatch(Call[] calldata calls) external payable onlyOwner {
        uint256 totalValue;
        for (uint256 i = 0; i < calls.length; i++) {
            totalValue += calls[i].value;
        }
        if (msg.value < totalValue) revert InsufficientETH();

        uint256 successCount;
        for (uint256 i = 0; i < calls.length; i++) {
            if (calls[i].to == address(0)) revert InvalidTarget();

            (bool success, bytes memory result) = calls[i].to.call{value: calls[i].value}(calls[i].data);

            if (success) {
                successCount++;
            }

            emit CallExecuted(calls[i].to, calls[i].value, success);

            if (!success) {
                if (result.length > 0) {
                    assembly {
                        revert(add(32, result), mload(result))
                    }
                }
                revert CallFailed(i);
            }
        }

        emit BatchCallExecuted(calls.length, successCount);
    }

    /**
     * @dev Execute multiple calls, continue even if some fail
     * @param calls Array of Call structs
     */
    function tryExecuteBatch(Call[] calldata calls) external payable onlyOwner returns (bool[] memory results) {
        uint256 totalValue;
        for (uint256 i = 0; i < calls.length; i++) {
            totalValue += calls[i].value;
        }
        if (msg.value < totalValue) revert InsufficientETH();

        results = new bool[](calls.length);
        uint256 successCount;

        for (uint256 i = 0; i < calls.length; i++) {
            if (calls[i].to == address(0)) {
                results[i] = false;
                continue;
            }

            (bool success,) = calls[i].to.call{value: calls[i].value}(calls[i].data);
            results[i] = success;

            if (success) {
                successCount++;
            }

            emit CallExecuted(calls[i].to, calls[i].value, success);
        }

        emit BatchCallExecuted(calls.length, successCount);
    }

    /**
     * @dev Transfer ownership
     * @param newOwner New owner address
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidNewOwner();
        address previousOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    /**
     * @dev Withdraw ETH balance
     */
    function withdrawETH() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance == 0) revert NoBalance();

        (bool success,) = owner.call{value: balance}("");
        if (!success) revert WithdrawFailed();
    }

    /**
     * @dev Withdraw ERC20 tokens
     * @param token ERC20 token address
     * @param amount Amount to withdraw
     */
    function withdrawERC20(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner, amount);
    }

    /**
     * @dev Withdraw ERC721 NFT
     * @param token ERC721 token address
     * @param tokenId Token ID to withdraw
     */
    function withdrawERC721(address token, uint256 tokenId) external onlyOwner {
        IERC721(token).safeTransferFrom(address(this), owner, tokenId);
    }

    /**
     * @dev Withdraw ERC1155 tokens
     * @param token ERC1155 token address
     * @param id Token ID
     * @param amount Amount to withdraw
     * @param data Additional data
     */
    function withdrawERC1155(address token, uint256 id, uint256 amount, bytes calldata data) external onlyOwner {
        IERC1155(token).safeTransferFrom(address(this), owner, id, amount, data);
    }

    /**
     * @dev Receive ETH
     */
    receive() external payable {}

    /**
     * @dev Fallback
     */
    fallback() external payable {}

    /**
     * @dev Handle ERC721 token reception
     */
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /**
     * @dev Handle ERC1155 single token reception
     */
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    /**
     * @dev Handle ERC1155 batch token reception
     */
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }

    /**
     * @dev Support ERC165 interface detection
     */
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 // ERC165
            || interfaceId == 0x150b7a02 // ERC721Receiver
            || interfaceId == 0x4e2312e0 // ERC1155Receiver-single
            || interfaceId == 0xbc197c81; // ERC1155Receiver-batch
    }
}
