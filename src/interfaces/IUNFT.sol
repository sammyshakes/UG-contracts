// SPDX-License-Identifier: MIT LICENSE

pragma solidity 0.8.13;


interface IUNFT {

    struct FighterYakuza {
        bool isRevealed;
        bool isFighter;
        bool isGen0;
        uint16 level;
        uint256 lastLevelUpgradeTime;
        uint8 rank;
        uint256 lastRankUpgradeTime;
        uint8 courage;
        uint8 cunning;
        uint8 brutality;
        uint64 mintedBlockNumber;
    }
    function addAdmin(address addr) external;
    function ownerOf(uint256 tokenId) external view returns (address);
    function burn(uint256 tokenId) external; // onlyAdmin
    function getTokenTraits(uint256 tokenId) external view returns (FighterYakuza memory); // onlyAdmin  
    function walletOfOwner(address owner) external view  returns (uint256[] memory) ;
    
}