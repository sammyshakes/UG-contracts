// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;
interface IRandomizer{
    function getSeeds(uint256, uint256, uint256) external view returns (uint256[] memory);
}
