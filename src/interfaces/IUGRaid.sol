// SPDX-License-Identifier: MIT LICENSE 

pragma solidity 0.8.13;

import "./IUGFYakuza.sol";
import "./IUGNFT.sol";

interface IUGRaid {

  struct Raid {
    uint8 levelTier;
    uint8 sizeTier;
    uint16 fightClubId;
    uint16 maxScars;
    uint32 maxSweat;
    uint32 id;
    uint32 revenue;
    uint32 timestamp;
  }

  struct RaiderEntry{
      uint8 size;
      uint8 yakFamily;
      uint32 sweat;
  }

  struct RaidEntryTicket {
    uint8 sizeTier;
    uint8 fighterLevel;
    uint8 yakuzaFamily;
    uint8 courage;
    uint8 brutality;
    uint8 cunning;
    uint8 knuckles;
    uint8 chains;
    uint8 butterfly;
    uint8 machete;
    uint8 katana;
    uint16 scars;
    uint32 sweat;
    uint32 fighterId;
    uint32 entryFee;
    uint32 winnings;
  }
  function getUnclaimedWeaponsCount(address user) external view returns (uint256 numWeapons, uint256 numWeaponTypes);
  function addIfRaidersInQueue(uint256[] memory tokenIds) external;
  function addTicketsToRaiderQueue(uint256[] memory packedTickets) external;
  function yakuzaRoundActive() external view returns (bool);
  function sweatRoundActive() external view returns (bool);
  function weaponsRoundActive() external view returns (bool);
  function referee(uint256) external;
  
  function claimRaiderBloodRewards() external;
  function getRaidCost(uint256, uint256) external view returns(uint256);
  function getRaiderQueueLength(uint8, uint8) external view returns(uint16);
  function getValueInBin(uint256 , uint256 , uint256 )external pure returns (uint256);
  function viewIfRaiderIsInQueue( uint256 tokenId) external view returns(bool);
  function setWeaponsRound(bool) external;//onlyOwner
  function setYakuzaRound(bool) external;//onlyOwner
  function setSweatRound(bool) external;//onlyOwner
  function setBaseRaidFee(uint256 newBaseFee) external; //onlyOwner
  function setRefereeBasePct(uint32 pct) external; //onlyOwner
  function setDevWallet(address) external;//onlyOwner
  function addAdmin(address) external;//onlyOwner
  function removeAdmin(address) external;//onlyOwner
}