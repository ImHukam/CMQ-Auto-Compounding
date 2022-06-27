// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract COMMUNIQUE is ERC20, Ownable {
    mapping(address => bool) private isPause;
    mapping(address => bool) private groupMap;
    address[] private groupArray;
    address private _owner;
    uint256 public maxTotalSupply;

    constructor(uint256 _maxTotalSupply) ERC20("COMMUNIQUE", "CMQ") {
        _owner = msg.sender;
        groupArray.push(msg.sender);
        groupMap[msg.sender] = true;
        maxTotalSupply = _maxTotalSupply;
    }

    /**
     * @dev Throws if called by any account other than the group.
     */
    modifier onlyGroup() {
        require(groupMap[msg.sender], "NotOneOfOwners");
        _;
    }

    /**
     * @dev Throws if called by any account other than the group.
     */
    modifier canRemove(address _address) {
        require(((groupMap[_address] && msg.sender == _address) || msg.sender == _owner), "NotAuthorized");
        _;
    }

    function changeMaxTotalSupply(uint256 _value) public onlyOwner {
        maxTotalSupply = _value;
    }

    function mint(address account, uint256 amount) external onlyOwner {
        uint256 estimate_totalSupply = totalSupply() + amount;
        require(maxTotalSupply >= estimate_totalSupply, "amount exceed max total supply");
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external onlyOwner {
        _burn(account, amount);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        require(isPause[msg.sender] == false, "transfer paused");
        address sender = _msgSender();
        _transfer(sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        require(isPause[from] == false, "from transfer paused");
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function multipleTransfer(address[] calldata _address, uint256[] calldata _amount) public {
        require(_address.length == _amount.length, "length should be equal for address and amount");
        require(isPause[msg.sender] == false, "multiple transfer paused");

        for (uint256 i = 0; i < _amount.length; i++) {
            IERC20(address(this)).transferFrom(msg.sender, _address[i], _amount[i]);
        }
    }

    /**
     * @dev Returns the address of the group.
     */
    function groupAddress() public view returns(address [] memory) {
        return groupArray;
    }

    /**
     * @dev add address to group
     *
     * Requirements:
     *
     * - `_address` cannot be the zero address.
     */
    function addToGroup(address _address) external onlyOwner {
        require(_address != address(0), "ERC20: add to group the zero address");
        require(!groupMap[_address], "AlreadyOwner");
        require(groupArray.length < 5, "MaxLimitReached");

        groupArray.push(_address);
        groupMap[_address] = true;
    }

    /**
     * @dev remove address from group
     *
     * Requirements:
     *
     * - `_address` cannot be the zero address.
     */
    function removeFromGroup(address _address) external canRemove(_address) {
        require(_address != address(0), "ERC20: remove from group the zero address");

        for (uint256 i = 0; i < groupArray.length; i++) {
            if (groupArray[i] == _address) {
                groupMap[groupArray[i]] = false;
                groupArray[i] = groupArray[groupArray.length - 1];
                groupArray.pop();
                break;
            }
        }
    }

    function pauseAddress(address _address, bool _pause) public onlyGroup {
        require(_address != address(0), "ERC20: pause the zero address");
        isPause[_address] = _pause;
    }

    function pause(address _address) public view returns(bool _isPause) {
        _isPause = isPause[_address];
    }
    
}