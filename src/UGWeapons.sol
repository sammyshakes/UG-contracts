// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import "./ERC1155/tokens/UGPackedBalance/UGPackedBalanceFungibles.sol";
import "./ERC1155/utils/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract UGWeapons is ERC1155PackedBalance, Ownable, ReentrancyGuard, Pausable {

  /*///////////////////////////////////////////////////////////////
                      WEAPON METALS BIT INDEXes
  //////////////////////////////////////////////////////////////*/
  //lowerweapons (1 - 15)
  //  STEEL = 0;
  //  BRONZE = 5;
  //  GOLD_WEAPON = 10;
  //  PLATINUM = 15;
  //  TITANIUM = 20;
  //  DIAMOND = 25;

  //  BROKEN_STEEL = 30;
  //  BROKEN_BRONZE = 35;
  //  BROKEN_GOLD_WEAPON = 40;
  //  BROKEN_PLATINUM = 45;
  //  BROKEN_TITANIUM = 50;

  // //weapons bit indexes (metal + weapon = bit index (tokenId)
  //  KNUCKLES = 1;
  //  CHAINS = 2;
  //  BUTTERFLY = 3;
  //  MACHETE = 4;
  //  KATANA = 5;

  uint8 constant SWEAT = 56;

  error MismatchArrays();
  error Unauthorized();
  error SweatTransferDenied();
  error InsufficientBalance();


  ///////////////////////////////////////////////////////////////////
  //             WEAPONS BALANCES                                ///
  /////////////////////////////////////////////////////////////////

  //holds total supply for weapons
  mapping(uint256 => uint256) private totalSupply;
  mapping(address => bool) private _admins;
  string private _name;
  string private _symbol;

  constructor() {
    _name = "UG Weapons Sweat";
    _symbol = "UGWS";
  }

  modifier onlyAdmin() {
    if(!_admins[_msgSender()]) revert Unauthorized();
    _;
  }

  function getTotalSupply(uint256 tokenId) external view returns (uint256) {
    (uint256 bin, uint256 index) = getIDBinIndex(tokenId);
    return getValueInBin(totalSupply[bin], index);
  }

  function mint(address _to, uint256 _id, uint256 _amount, bytes memory _data) external onlyAdmin {
    _mint( _to,  _id,  _amount, _data);
  }

  function _mint(address _to, uint256 _id, uint256 _amount, bytes memory _data)
    internal
  {
    //Add _amount
    _updateIDBalance(_to,   _id, _amount, Operations.Add); // Add amount to recipient
    
    // Load first bin and index where the token ID balance exists
    (uint256 bin, uint256 index) = getIDBinIndex(_id);

    // update total supply
    totalSupply[bin] = _viewUpdateBinValue(totalSupply[bin], index, _amount, Operations.Add);
    
    // Emit event
    emit TransferSingle(msg.sender, address(0x0), _to, _id, _amount);

    // Calling onReceive method if recipient is contract
    _callonERC1155Received(address(0x0), _to, _id, _amount, gasleft(), _data);
  }

  function batchMint(
    address _to, 
    uint256[] memory _ids, 
    uint256[] memory _amounts, 
    bytes memory _data
  ) external onlyAdmin {
    _batchMint( _to, _ids,  _amounts, _data);
  }

  function _batchMint(
    address _to, 
    uint256[] memory _ids, 
    uint256[] memory _amounts, 
    bytes memory _data
  ) internal {
    if(_ids.length != _amounts.length) revert MismatchArrays();

    if (_ids.length > 0) {
      // Load first bin and index where the token ID balance exists
      (uint256 bin, uint256 index) = getIDBinIndex(_ids[0]);

      // Balance for current bin in memory (initialized with first transfer)
      uint256 balTo = _viewUpdateBinValue(balances[_to][bin], index, _amounts[0], Operations.Add);
      uint256 ttlSupply = _viewUpdateBinValue(totalSupply[bin], index, _amounts[0], Operations.Add);
      

      // Number of transfer to execute
      uint256 nTransfer = _ids.length;

      // Last bin updated
      uint256 lastBin = bin;

      for (uint256 i = 1; i < nTransfer; i++) {
        (bin, index) = getIDBinIndex(_ids[i]);

        // If new bin
        if (bin != lastBin) {
          // Update storage balance of previous bin
          balances[_to][lastBin] = balTo;
          balTo = balances[_to][bin];

          totalSupply[lastBin] = ttlSupply;
          ttlSupply = totalSupply[bin];

          // Bin will be the most recent bin
          lastBin = bin;
        }

        // Update memory balance
        balTo = _viewUpdateBinValue(balTo, index, _amounts[i], Operations.Add);
        ttlSupply = _viewUpdateBinValue(ttlSupply, index, _amounts[i], Operations.Add);
      }

      // Update storage of the last bin visited
      balances[_to][bin] = balTo;
      totalSupply[bin] = ttlSupply;
    }

    // //Emit event
    emit TransferBatch(msg.sender, address(0x0), _to, _ids, _amounts);

    // Calling onReceive method if recipient is contract
    _callonERC1155BatchReceived(address(0x0), _to, _ids, _amounts, gasleft(), _data);
  }

  function burn(address _from, uint256 _id, uint256 _amount) external onlyAdmin{
    if(balanceOf(_from, _id) < _amount) revert InsufficientBalance();
    _burn( _from,  _id,  _amount);
  }

  function _burn(address _from, uint256 _id, uint256 _amount) internal {
    // Substract _amount
    _updateIDBalance(_from, _id, _amount, Operations.Sub);
    uint256 bin;
    uint256 index;

    // Get bin and index of _id
    (bin, index) = getIDBinIndex(_id);

    // Update balance
    totalSupply[bin] = _viewUpdateBinValue(totalSupply[bin], index, _amount, Operations.Sub);
    
    // Emit event
    emit TransferSingle(msg.sender, _from, address(0x0), _id, _amount);
  }

  function batchBurn(address _from, uint256[] memory _ids, uint256[] memory _amounts) external onlyAdmin {
    _batchBurn( _from, _ids,  _amounts);
  }

  function _batchBurn(address _from, uint256[] memory _ids, uint256[] memory _amounts)
    internal 
  {
    // Number of burning to execute
    uint256 nBurn = _ids.length;
    if(nBurn != _amounts.length) revert MismatchArrays();

    // Executing all burning
    for (uint256 i = 0; i < nBurn; i++) {
      uint256 bin;
      uint256 index;

      // Get bin and index of _id
      (bin, index) = getIDBinIndex(_ids[i]);

      // Update balance
      balances[_from][bin] = _viewUpdateBinValue(balances[_from][bin], index, _amounts[i], Operations.Sub);
      totalSupply[bin] = _viewUpdateBinValue(totalSupply[bin], index, _amounts[i], Operations.Sub);
      
    }

    // Emit batch burn event
    emit TransferBatch(msg.sender, _from, address(0x0), _ids, _amounts);
  }

  function safeTransferFrom(
    address _from, 
    address _to, 
    uint256 _id, 
    uint256 _amount, 
    bytes memory _data
  ) public override {
    // Requirements
    require((msg.sender == _from) || isApprovedForAll(_from, msg.sender), " INVALID_OPERATOR");
    require(_to != address(0)," INVALID_RECIPIENT");
    // require(_amount <= balances);  Not necessary since checked with _viewUpdateBinValue() checks
    if(_id == SWEAT && !_admins[msg.sender]) revert SweatTransferDenied();

    _safeTransferFrom(_from, _to, _id, _amount);
    _callonERC1155Received(_from, _to, _id, _amount, gasleft(), _data);
  }

  function safeBatchTransferFrom(
    address _from, 
    address _to, 
    uint256[] memory _ids, 
    uint256[] memory _amounts, 
    bytes memory _data
  ) public override {
    // Requirements
    require((msg.sender == _from) || isApprovedForAll(_from, msg.sender), " INVALID_OPERATOR");
    require(_to != address(0)," INVALID_RECIPIENT");

    _safeBatchTransferFrom(_from, _to, _ids, _amounts);
    _callonERC1155BatchReceived(_from, _to, _ids, _amounts, gasleft(), _data);
  }

  /**
   * @notice Send multiple types of Tokens from the _from address to the _to address (with safety call)
   * @dev Arrays should be sorted so that all ids in a same storage slot are adjacent (more efficient)
   * @param _from     Source addresses
   * @param _to       Target addresses
   * @param _ids      IDs of each token type
   * @param _amounts  Transfer amounts per token type
   */
  function _safeBatchTransferFrom(
    address _from, 
    address _to, 
    uint256[] memory _ids, 
    uint256[] memory _amounts
  ) internal override {
    uint256 nTransfer = _ids.length; // Number of transfer to execute
    require(nTransfer == _amounts.length, "INVALID_ARRAYS_LENGTH");

    if (_from != _to && nTransfer > 0) {

      // Load first bin and index where the token ID balance exists
      (uint256 bin, uint256 index) = getIDBinIndex(_ids[0]);

      // Balance for current bin in memory (initialized with first transfer)
      uint256 balFrom = _viewUpdateBinValue(balances[_from][bin], index, _amounts[0], Operations.Sub);
      uint256 balTo = _viewUpdateBinValue(balances[_to][bin], index, _amounts[0], Operations.Add);

      // Last bin updated
      uint256 lastBin = bin;

      for (uint256 i = 1; i < nTransfer; i++) {
        if(_ids[i] == SWEAT && !_admins[msg.sender]) revert SweatTransferDenied();

        
        (bin, index) = getIDBinIndex(_ids[i]);

        // If new bin
        if (bin != lastBin) {
          // Update storage balance of previous bin
          balances[_from][lastBin] = balFrom;
          balances[_to][lastBin] = balTo;

          balFrom = balances[_from][bin];
          balTo = balances[_to][bin];

          // Bin will be the most recent bin
          lastBin = bin;
        }

        // Update memory balance
        balFrom = _viewUpdateBinValue(balFrom, index, _amounts[i], Operations.Sub);
        balTo = _viewUpdateBinValue(balTo, index, _amounts[i], Operations.Add);
      }

      // Update storage of the last bin visited
      balances[_from][bin] = balFrom;
      balances[_to][bin] = balTo;

    // If transfer to self, just make sure all amounts are valid
    } else {
      for (uint256 i = 0; i < nTransfer; i++) {
        require(balanceOf(_from, _ids[i]) >= _amounts[i], " UNDERFLOW");
      }
    }
    //update type balances

    // Emit event
    emit TransferBatch(msg.sender, _from, _to, _ids, _amounts);
  }

  function name() external view returns (string memory){
    return _name;
  }

  function symbol() external view returns (string memory){
    return _symbol;
  }

  function addAdmin(address addr) external onlyOwner {
    _admins[addr] = true;
  }

  function removeAdmin(address addr) external onlyOwner {
    delete _admins[addr];
  }
}