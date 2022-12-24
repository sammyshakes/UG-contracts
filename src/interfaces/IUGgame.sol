// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;


interface IUGgame{

    struct RaiderEntry{
        uint8 size;
        uint8 yakFamily;
        uint32 sweat;
    }
    function MAXIMUM_BLOOD_SUPPLY() external view returns (uint256);
    function getFighterLevelUpBloodCost(uint16, uint256) external view returns(uint256);
    function getRingLevelUpBloodCost(uint16, uint256, uint256) external view returns(uint256);
    function getAmuletLevelUpBloodCost(uint16, uint256, uint256) external view returns(uint256);
    function levelUpFighters(uint256[] calldata, uint256[] memory, bool) external returns(uint256);
    function levelUpRing(uint256, uint256) external returns(uint256);
    function levelUpAmulet(uint256, uint256) external returns(uint256);
    function levelUpFightClubs(uint256[] calldata, uint256[] memory, uint256[] memory) external returns(uint256);
    function levelUpForges(uint256[] calldata, uint256[] memory) external returns(uint256);
    function sizeUpForges(uint256[] calldata) external returns(uint256);
    function getFightClubLevelUpBloodCost(uint16, uint16, uint8, uint8) external view  returns(uint256);
    function setFightClubLevelCostAdjustmentPct(uint16 pct) external; //onlyOwner
    function setFighterLevelCostAdjustmentPct(uint16 pct) external; //onlyOwner
    function setRingLevelCostAdjustmentPct(uint16 pct) external;//onlyOwner
    function setAmuletLevelCostAdjustmentPct(uint16 pct) external;//onlyOwner
    function setMaximumBloodSupply(uint256) external;//onlyOwner
    function setRingBloodMintCost(uint256) external;//onlyOwner
    function setAmuletBloodMintCost(uint256) external;//onlyOwner
    function setFightClubBloodMintCost(uint256) external;//onlyOwner
    function setForgeBloodMintCost(uint256) external;//onlyOwner

}