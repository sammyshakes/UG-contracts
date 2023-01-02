 // SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

interface IUGNFT2 {
 
    struct FighterYakuza {
        bool isFighter;
        uint8 Gen;
        uint8 level;
        uint8 rank;
        uint8 courage;
        uint8 cunning;
        uint8 brutality;
        uint8 knuckles;
        uint8 chains;
        uint8 butterfly;
        uint8 machete;
        uint8 katana;
        uint16 scars;
        uint16 imageId;
        uint32 lastLevelUpgradeTime;
        uint32 lastRankUpgradeTime;
        uint32 lastRaidTime;
    }  
    //weapons scores used to identify "metal"
    // steel = 10, bronze = 20, gold = 30, platinum = 50 , titanium = 80, diamond = 100
    struct RaidStats {
        uint8 knuckles;
        uint8 chains;
        uint8 butterfly;
        uint8 machete;
        uint8 katana;
        uint16 scars;
        uint32 fighterId;
    }


    function safeBatchTransferFrom(address _from, address _to, uint256[] calldata _ids, uint256[] calldata _amounts, bytes calldata _data) external;
    function getPackedFighters(uint256[] calldata tokenIds) external view returns (uint256[] memory);
    function setBaseURI(string calldata uri) external;//onlyOwner
    function tokenURIs(uint256[] calldata tokenId) external view returns (string[] memory) ;
    function batchMigrateFYakuza(address _to, uint256[] calldata v1TokenIds, FighterYakuza[] calldata oldFighters) external;//onlyAdmin 
    function checkUserBatchBalance(address user, uint256[] calldata tokenIds) external view returns (bool);
    function getFighter(uint256 tokenId) external view returns (FighterYakuza memory);
    function getFighters(uint256[] calldata) external view returns (FighterYakuza[] memory);
    function levelUpFighters(uint256[] calldata, uint256[] calldata) external; // onlyAdmin
    function addAdmin(address) external; // onlyOwner 
    function removeAdmin(address) external; // onlyOwner
    function ttlFYakuzas() external view returns (uint256);
    function setRaidTraitsFromPacked( uint256[] calldata raidStats) external;    
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function setFighter( uint256 tokenId, FighterYakuza memory FY) external;
}