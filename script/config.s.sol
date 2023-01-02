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
import '../src/RaidEntry.sol';
import '../src/UGFightClubAlley.sol';
import '../src/UGForgeSmith.sol';

contract Config is Script {

    // Deployments
    IUGFYakuza public ugFYakuza;
    IUGNFT public ugNFT;
    UGYakDen public ugYakDen;
    UGArena public ugArena;
    IUBlood public uBLOOD;
    UGgame public ugGame;
    UGRaid public ugRaid;
    Randomizer public randomizer;
    UGWeapons public ugWeapons;
    RaidEntry public raidEntry;
    UGFightClubAlley public fclubAlley;
    UGForgeSmith public ugForgeSmith;

    address bloodOwnerTestnet = 0x5b8F11C2c1E33f0857c12Da896bF7c86A8101023;//testnet blood owner
    address bloodContractTestnet = 0x649A53b481031ff57367F672e07d0A488ad421d9;//testnet blood addy
        


    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
            //Deploy Contracts
            randomizer = Randomizer(vm.envAddress("RANDOMIZER_TESTNET_ADDRESS"));
            ugFYakuza = IUGFYakuza(vm.envAddress("UGFYAKUZA_TESTNET_ADDRESS"));
            ugNFT =  IUGNFT(vm.envAddress("UGNFT2_TESTNET_ADDRESS"));
            ugWeapons = UGWeapons(vm.envAddress("UGWEAPONS2_TESTNET_ADDRESS"));
            ugForgeSmith = UGForgeSmith(vm.envAddress("UGFORGESMITH2_TESTNET_ADDRESS"));
            uBLOOD = IUBlood(bloodContractTestnet);//testnet blood addy
            ugYakDen = UGYakDen( vm.envAddress("UGYAKDEN_TESTNET_ADDRESS"));
            fclubAlley = UGFightClubAlley( vm.envAddress("FIGHTCLUBALLEY_TESTNET_ADDRESS"));
            ugArena = UGArena(vm.envAddress("UGARENA_TESTNET_ADDRESS"));
            
            ugRaid = UGRaid(vm.envAddress("UGRAID_TESTNET_ADDRESS"));
            raidEntry = RaidEntry( vm.envAddress("RAIDENTRY_TESTNET_ADDRESS"));

            ugGame = UGgame(vm.envAddress("UGGAME_TESTNET_ADDRESS"));  

                

            //turn on  minting
            ugGame.setAmuletMintActive(true);
            ugGame.setRingMintActive(true);
            ugGame.setForgeMintActive(true);
            ugGame.setFightClubMintActive(true);

            ugRaid.setDevWallet(bloodOwnerTestnet);
            ugRaid.addAdmin(address(raidEntry));
            ugWeapons.addAdmin(address(ugRaid));
            ugWeapons.addAdmin(address(raidEntry));
            
            ugGame.setDevWallet(bloodOwnerTestnet);

            

            uBLOOD.addAdmin(address(ugGame));
            uBLOOD.addAdmin(address(ugRaid));
            uBLOOD.addAdmin(address(raidEntry));
            uBLOOD.addAdmin(address(ugArena));
            uBLOOD.addAdmin(address(ugYakDen));        
            uBLOOD.addAdmin(address(fclubAlley));

            //phase switches
            // ugRaid.setWeaponsRound(true);
            // ugRaid.setYakuzaRound(true); 

        vm.stopBroadcast();
    }
}