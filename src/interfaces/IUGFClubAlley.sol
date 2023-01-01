// SPDX-License-Identifier: MIT LICENSE 

pragma solidity 0.8.13;

interface IUGFClubAlley {
  function payRevenueToFightClubs(uint256 amount) external;  
  function claimFightClubs(uint256[] memory tokenIds, bool unstake) external returns(uint256[] memory);
}