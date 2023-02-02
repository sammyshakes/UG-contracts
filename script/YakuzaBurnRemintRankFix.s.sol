// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/interfaces/IUGFYakuza.sol";
import "../src/UGArena.sol";

contract YakuzaBurnRemintRankFix is Script {
    // Deployments
    IUGFYakuza public ugFYakuza;
    UGArena public ugArena2;

    address ugOwner = 0x715ac5FC4c4587Fa8e425Afc1D1207Cffb7b66d5; // ug owner
    address devWallet = 0x18CDFFA4D6425C3674e6085d96dE413cf4634a5d; 

    address user = 0x850Baf1eA642873B493c1C2696da77FaB43D5609;

    uint256[] tokenIds = [15175,15176];

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
