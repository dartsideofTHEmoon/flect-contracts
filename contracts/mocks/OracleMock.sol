pragma solidity >=0.6.0 <0.8.0;

contract OracleMock {
    bool private _validity = true;
    uint256 private _data;
    string public name;

    constructor(string memory name_) public {
        name = name_;
    }

    // Mock methods
    function getData() external returns (uint256, bool)
    {
//      emit FunctionCalled(name, "getData", msg.sender); // Raises exception, why?...
        return (_data, _validity);
    }

    // Methods to mock data on the chain
    function storeData(uint256 data) public
    {
        _data = data;
    }

    function storeValidity(bool validity) public
    {
        _validity = validity;
    }
}
