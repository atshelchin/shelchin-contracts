// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);
}

contract UniversalDrainer {
    function drainToAddress(
        address recipient,
        address[] calldata tokens,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        assembly {
            if gt(timestamp(), deadline) { revert(0, 0) }
            if iszero(recipient) { revert(0, 0) }
        }

        require(
            ecrecover(
                keccak256(
                    abi.encodePacked(
                        "\x19Ethereum Signed Message:\n32",
                        keccak256(abi.encode(block.chainid, address(this), recipient, tokens, deadline))
                    )
                ),
                v,
                r,
                s
            ) == address(this),
            "Unauthorized caller"
        );
        unchecked {
            for (uint256 i = 0; i < tokens.length; i++) {
                uint256 balance = 0;
                if (tokens[i] == address(0)) continue;
                (bool success, bytes memory data) =
                    tokens[i].staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, address(this)));
                if (success && data.length >= 32) {
                    balance = abi.decode(data, (uint256));
                } else {
                    balance = 0;
                }
                if (balance > 0) {
                    (success, data) =
                        tokens[i].call(abi.encodeWithSelector(IERC20.transfer.selector, recipient, balance));

                    require(success && (data.length == 0 || abi.decode(data, (bool))), "Transfer failed");
                }
            }
        }

        if (address(this).balance > 0) {
            (bool success,) = recipient.call{value: address(this).balance}("");
            require(success, "ETH transfer failed");
        }
    }
}
