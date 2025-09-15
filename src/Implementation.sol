// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title Implementation
 * @dev Example implementation contract for minimal proxy pattern
 */
contract Implementation {
    address public owner;
    string public name;
    uint256 public value;
    bool private initialized;

    event Initialized(address owner, string name, uint256 value);
    event ValueChanged(uint256 oldValue, uint256 newValue);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier initializer() {
        require(!initialized, "Already initialized");
        _;
        initialized = true;
    }

    /**
     * @dev Initialize the proxy instance
     * @param _owner The owner of this proxy instance
     * @param _name The name for this instance
     * @param _value Initial value
     */
    function initialize(
        address _owner,
        string memory _name,
        uint256 _value
    ) external initializer {
        owner = _owner;
        name = _name;
        value = _value;
        emit Initialized(_owner, _name, _value);
    }

    function setValue(uint256 _newValue) external onlyOwner {
        uint256 oldValue = value;
        value = _newValue;
        emit ValueChanged(oldValue, _newValue);
    }

    function increment() external onlyOwner {
        value++;
    }

    function getData() external view returns (address, string memory, uint256) {
        return (owner, name, value);
    }
}
