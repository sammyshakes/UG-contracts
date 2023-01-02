// SPDX-License-Identifier: MIT LICENSE

pragma solidity 0.8.13;


interface IUGForgeSmith { 
    function addToTotalForgeLevelStaked (uint256) external;
    function stakeForges(uint256[] calldata tokenIds) external ;
    function unstakeFightclubs(uint256[] calldata tokenIds) external ;
    function calculateAllStakingRewards(uint256[] memory tokenIds) external view returns (uint256[] memory weapons, uint256[] memory amounts);
    function calculateStakingRewards(uint256 tokenId) external view returns (uint256 weapon, uint256 owed);
    function claimAllStakingRewards(address user) external ;
    function getStakedForgeIDsForUser(address user) external view returns (uint256[] memory);
}