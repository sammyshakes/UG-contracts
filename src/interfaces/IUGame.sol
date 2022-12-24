// SPDX-License-Identifier: MIT LICENSE

pragma solidity 0.8.13;

import "./IUNFT.sol";

interface IUGame {
    function addAdmin(address addr) external;
    function MAXIMUM_BLOOD_SUPPLY() external returns (uint256);
    function getOwnerOfFYToken(uint256 tokenId) external view returns(address ownerOf);
    function getFyTokenTraits(uint256 tokenId) external view returns (IUNFT.FighterYakuza memory);
    function calculateStakingRewards(uint256 tokenId) external view returns (uint256 owed);
}