// SPDX-License-Identifier: MIT LICENSE 

pragma solidity 0.8.13;



interface IRaidEntry {

   struct RaiderEntry{
      uint8 size;
      uint8 yakFamily;
      uint32 sweat;
  }

  function enterRaid(uint256[] calldata, RaiderEntry[] calldata) external  returns(uint256 ttlBloodEntryFee);
  function setDevWallet(address) external;//onlyOwner
  function addAdmin(address) external;//onlyOwner
  function removeAdmin(address) external;//onlyOwner
}