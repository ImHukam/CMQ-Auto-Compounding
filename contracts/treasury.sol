// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CMQRewardTreasury is Ownable {
    address public CMQ = 0x5456c2Af0c192C1928e8369562c2Cb9eb9662926;

    IERC20 public cmq = IERC20(CMQ);
    address public VyncCmqStakingPool;
    address public cmqStakingPool;

    modifier onlyStakingPool() {
        require(
            VyncCmqStakingPool == msg.sender || cmqStakingPool == msg.sender,
            "not authorized"
        );
        _;
    }

    function set_cmq(address _cmq) external onlyOwner {
        CMQ = _cmq;
        cmq = IERC20(CMQ);
    }

    function set_stakingpool(address _vyncCmq, address _cmq)
        external
        onlyOwner
    {
        VyncCmqStakingPool = _vyncCmq;
        cmqStakingPool = _cmq;
    }

    function treasuryBalance() public view returns (uint256) {
        return cmq.balanceOf(address(this));
    }

    function withdrawCmq(uint256 _amount, address _to) external onlyOwner {
        cmq.transfer(_to, _amount);
    }

    function send(address recipient, uint256 amount) external onlyStakingPool {
        require(
            cmq.balanceOf(address(this)) >= amount,
            "reward token not available into contract"
        );
        cmq.transfer(recipient, amount);
    }

    function transferAnyERC20Token(
        address _tokenAddress,
        address _to,
        uint256 _amount
    ) public onlyOwner {
        IERC20(_tokenAddress).transfer(_to, _amount);
    }
}
