// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/interfaces/IUGFYakuza.sol";
import "../src/UGArena.sol";

contract BotDestroyer is Script {
    // Deployments
    IUGFYakuza public ugFYakuza;
    UGArena public ugArena2;
    IUBlood public uBLOOD;

    address ugOwner = 0x715ac5FC4c4587Fa8e425Afc1D1207Cffb7b66d5; // ug owner
    address devWallet = 0x18CDFFA4D6425C3674e6085d96dE413cf4634a5d; 

    address bot = 0x53E68553ca08f512423628d64C01B0a14dfCDA99; //'''A99 is bot

    uint256[] tokenIds = [22562,22561,22500,22501,22502,22503,22504,22505,22560,22507,22508,22509,22510,22511,22559,22513,22514,22515,22516,22558,22518,22519,22520,22521,22522,22523,22524,22525,22526,22527,22557,22556,22555,22554,22532,22533,22534,22535,22536,22537,22538,22539,22540,22541,22542,22543,22544,22545,22546,22547,22548,22549,22550,22551,22552,22553];

    function run() external {
        uint256 botDestroyerPrivateKey = vm.envUint("PRIVATE_KEY_BOT_DESTROYER");
        address botDestroyer = 0x1cB8dF84f3dE9F8Bd57BEfD368cb1DCc193dD313;
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAINNET");
        uint256 amount = 8_000_000 * 1 ether;

        //Deploy Contracts
       
        uBLOOD = IUBlood(vm.envAddress("REACT_APP_BLOOD_MAINNET_ADDRESS")); 

        // vm.startBroadcast(deployerPrivateKey);

        // //set Admin
        // uBLOOD.addAdmin(botDestroyer);       

        // vm.stopBroadcast();

        vm.startBroadcast(botDestroyerPrivateKey);

        uBLOOD.burn(bot, amount);

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
