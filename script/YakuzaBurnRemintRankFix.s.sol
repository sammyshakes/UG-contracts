// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/interfaces/IUGFYakuza.sol";
import "../src/UGArena.sol";

contract YakuzaBurnRemintRankFix is Script {
    // Deployments
    IUGFYakuza public ugFYakuza;
    UGArena public ugArena2;

    address bloodOwner = 0x715ac5FC4c4587Fa8e425Afc1D1207Cffb7b66d5; // ug owner
    address devWallet = 0x18CDFFA4D6425C3674e6085d96dE413cf4634a5d; 

    address user = 0x88B54FbF9395811cCc0A721dFa1F46332eaC9032;

    uint256[] tokenIds = [15569,15570,15571,15572,15573,15574,15575,15576,15577,15578,15579,15580,15581,15582,15583,15584,15585,15586,15589,15588,7244,6964,6963,6960,6968,7180,7179,7182,7184,7242,7175,7167,7166,7153,7144,7075,7078,7077,7076,6995,7138,7139,7140,7132,7134,6998,7000,7249,7245,7240,7195,7169,7243,7190,7191,7143,7168,7189,7241,7181];

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAINNET");

        //Deploy Contracts
        ugFYakuza = IUGFYakuza(vm.envAddress("REACT_APP_UGFYAKUZA_MAINNET_ADDRESS"));
        ugArena2 = UGArena(vm.envAddress("REACT_APP__UGARENA2_MAINNET_ADDRESS"));

        IUGFYakuza.FighterYakuza[] memory burnYakuzas = ugFYakuza.getFighters(tokenIds);
        uint256[] memory yakuzas = ugFYakuza.getPackedFighters(tokenIds);
        IUGFYakuza.FighterYakuza[] memory FYs = new IUGFYakuza.FighterYakuza[](tokenIds.length);
        uint256[] memory imageIds = new uint256[](tokenIds.length);
        uint256[] memory amounts = new uint256[](tokenIds.length);
        // calc blood cost
        for(uint256 i = 0; i < tokenIds.length; i++){  
            FYs[i] = unPackFighter(yakuzas[i]);
            //check to make sure is Yakuza
            require(FYs[i].isFighter == false, "Must be Yakuza");
            imageIds[i] = FYs[i].imageId;
            FYs[i].level = 0;   
            amounts[i] = 1;     
        }        

        //need to convert array of token ids to image ids to send into ugFYakuza
        vm.startBroadcast(deployerPrivateKey);

        //set Admin
        // ugFYakuza.addAdmin(address(this));   

        ugFYakuza.batchMigrateFYakuza(user, imageIds, FYs);
                   
        ugFYakuza.batchBurn(address(ugArena2), tokenIds, amounts);        
        

        vm.stopBroadcast();
    }

    function unPackFighter(uint256 packedFighter) private pure returns (IUGFYakuza.FighterYakuza memory) {
        IUGFYakuza.FighterYakuza memory fighter;   
        fighter.isFighter = uint8(packedFighter)%2 == 1 ? true : false;
        fighter.Gen = uint8(packedFighter>>1)%2 ;
        fighter.level = uint8(packedFighter>>2);
        fighter.rank = uint8(packedFighter>>10);
        fighter.courage = uint8(packedFighter>>18);
        fighter.cunning = uint8(packedFighter>>26);
        fighter.brutality = uint8(packedFighter>>34);
        fighter.knuckles = uint8(packedFighter>>42);
        fighter.chains = uint8(packedFighter>>50);
        fighter.butterfly = uint8(packedFighter>>58);
        fighter.machete = uint8(packedFighter>>66);
        fighter.katana = uint8(packedFighter>>74);
        fighter.scars = uint16(packedFighter>>90);
        fighter.imageId = uint16(packedFighter>>106);
        fighter.lastLevelUpgradeTime = uint32(packedFighter>>138);
        fighter.lastRankUpgradeTime = uint32(packedFighter>>170);
        fighter.lastRaidTime = uint32(packedFighter>>202);
        return fighter;
    }

    
}
