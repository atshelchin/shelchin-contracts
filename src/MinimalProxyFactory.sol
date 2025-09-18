// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title MinimalProxyFactory
 * @dev EIP-1167 Minimal Proxy Factory for deploying cheap clones
 */
contract MinimalProxyFactory {
    event ProxyDeployed(address indexed implementation, address proxy, bytes32 salt);

    /**
     * @dev Deploy a minimal proxy clone of an implementation contract
     * @param implementation The address of the implementation contract to clone
     * @param salt Unique salt for deterministic deployment
     */
    function deployProxy(address implementation, bytes32 salt) external returns (address proxy) {
        require(implementation != address(0), "Invalid implementation");

        bytes memory bytecode = _getProxyBytecode(implementation);

        assembly {
            proxy := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
            if iszero(extcodesize(proxy)) { revert(0, 0) }
        }

        emit ProxyDeployed(implementation, proxy, salt);
    }

    /**
     * @dev Deploy and initialize a proxy in one transaction
     * @param implementation The address of the implementation contract
     * @param salt Unique salt for deterministic deployment
     * @param data Initialization calldata
     */
    function deployProxyAndCall(address implementation, bytes32 salt, bytes calldata data)
        external
        returns (address proxy)
    {
        proxy = this.deployProxy(implementation, salt);

        if (data.length > 0) {
            (bool success, bytes memory result) = proxy.call(data);
            if (!success) {
                if (result.length > 0) {
                    assembly {
                        revert(add(32, result), mload(result))
                    }
                }
                revert("Initialization failed");
            }
        }
    }

    /**
     * @dev Calculate the address where a proxy will be deployed
     * @param implementation The implementation contract address
     * @param salt The salt for deployment
     */
    function computeProxyAddress(address implementation, bytes32 salt) external view returns (address) {
        bytes memory bytecode = _getProxyBytecode(implementation);
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        return address(uint160(uint256(hash)));
    }

    /**
     * @dev Generate EIP-1167 minimal proxy bytecode
     * @param implementation The implementation address
     */
    function _getProxyBytecode(address implementation) private pure returns (bytes memory) {
        return abi.encodePacked(
            hex"3d602d80600a3d3981f3363d3d373d3d3d363d73", implementation, hex"5af43d82803e903d91602b57fd5bf3"
        );
    }
}
