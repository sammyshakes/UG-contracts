// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/interfaces/IUGNFT.sol";
import "../src/interfaces/IUGFYakuza.sol";
import "../src/UGYakDen.sol";
import "../src/UGRaid.sol";
import "../src/UGgame.sol";
import "../src/UGWeapons.sol";
import "../src/Randomizer.sol";
import "../src/UGArena.sol";
import "../src/RaidEntry.sol";
import "../src/UGFightClubAlley.sol";
import "../src/UGForgeSmith.sol";

contract Deploy is Script {
    // Deployments
    IUGFYakuza public ugFYakuza;
    IUGNFT public ugNFT;
    UGYakDen public ugYakDen;
    UGArena public ugArena;
    UGArena public ugArenaNew;
    IUBlood public uBLOOD;
    UGgame public ugGame;
    UGRaid public ugRaid;
    Randomizer public randomizer;
    UGWeapons public ugWeapons;
    RaidEntry public raidEntry;
    UGFightClubAlley public fclubAlley;
    UGForgeSmith public ugForgeSmith;

    address bloodOwnerTestnet = 0x5b8F11C2c1E33f0857c12Da896bF7c86A8101023; //testnet blood owner
    address bloodContractTestnet = 0x649A53b481031ff57367F672e07d0A488ad421d9; //testnet blood addy

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        //Deploy Contracts
        //Deploy Contracts
        randomizer = Randomizer(vm.envAddress("RANDOMIZER_TESTNET_ADDRESS"));
        ugFYakuza = IUGFYakuza(vm.envAddress("UGFYAKUZA_TESTNET_ADDRESS"));
        ugNFT = IUGNFT(vm.envAddress("UGNFT2_TESTNET_ADDRESS"));
        ugWeapons = UGWeapons(vm.envAddress("UGWEAPONS2_TESTNET_ADDRESS"));
        ugYakDen = UGYakDen(vm.envAddress("REACT_APP_UGYAKDEN_TESTNET_ADDRESS"));
        fclubAlley = UGFightClubAlley(vm.envAddress("REACT_APP_FIGHTCLUBALLEY_TESTNET_ADDRESS"));
        ugArena = UGArena(vm.envAddress("REACT_APP__UGARENA2_TESTNET_ADDRESS"));
        ugArenaNew = UGArena(vm.envAddress("REACT_APP_UGARENA3_TESTNET_ADDRESS"));
        raidEntry = RaidEntry(vm.envAddress("REACT_APP_RAIDENTRY4_TESTNET_ADDRESS"));
        ugGame = UGgame(vm.envAddress("REACT_APP_UGGAME5_TESTNET_ADDRESS"));
        
        uBLOOD = IUBlood(bloodContractTestnet); //testnet blood addy

        vm.startBroadcast(deployerPrivateKey);

        ugForgeSmith = new UGForgeSmith(
            address(ugNFT),
            address(ugFYakuza),
            bloodContractTestnet,
            address(ugWeapons),            
            address(ugArena),
            bloodOwnerTestnet
        );
       

        
        //set Admins
        
        ugArena.addAdmin(address(ugForgeSmith));
        
        ugForgeSmith.addAdmin(address(ugGame));
        ugFYakuza.addAdmin(address(ugForgeSmith));
        ugForgeSmith.addAdmin(address(ugGame));
        
        ugWeapons.addAdmin(address(ugForgeSmith));

        

        ugGame.setDevWallet(bloodOwnerTestnet);
        
        uBLOOD.addAdmin(address(ugForgeSmith));
        
        ugForgeSmith.setContracts(
            address(ugNFT), 
            address(ugFYakuza), 
            address(uBLOOD), 
            address(ugWeapons), 
            address(ugArenaNew)
        );

        vm.stopBroadcast();
    }
}
