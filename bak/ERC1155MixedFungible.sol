// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

//this version was adapted from Enjin to fit the solmate implementation of ERC1155

//importing 0xSequence version of ERC1155
import "./ERC1155/tokens/ERC1155/ERC1155.sol";
//import "@solmate/tokens/ERC1155.sol";

/**
    @dev Extension to ERC1155 for Mixed Fungible and Non-Fungible Items support
    The main benefit is sharing of common type information, just like you do when
    creating a fungible id.
*/
contract ERC1155MixedFungible is ERC1155 {

    // Use a split bit implementation.
    // Store the type in the upper 128 bits..
    uint256 constant TYPE_MASK = uint256(type(uint128).max) << 128;

    // ..and the non-fungible index in the lower 128
    uint256 constant NF_INDEX_MASK = type(uint128).max;

    // The top bit is a flag to tell if this is a NFI.
    uint256 constant TYPE_NF_BIT = 1 << 255;

    mapping (uint256 => address) public nfOwners;

    // Only to make code clearer. Should not be functions
    function isNonFungible(uint256 _id) public pure returns(bool) {
        return _id & TYPE_NF_BIT == TYPE_NF_BIT;
    }
    function isFungible(uint256 _id) public pure returns(bool) {
        return _id & TYPE_NF_BIT == 0;
    }
    function getNonFungibleIndex(uint256 _id) public pure returns(uint256) {
        return _id & NF_INDEX_MASK;
    }
    function getNonFungibleBaseType(uint256 _id) public pure returns(uint256) {
        return _id & TYPE_MASK;
    }
    function isNonFungibleBaseType(uint256 _id) public pure returns(bool) {
        // A base type has the NF bit but does not have an index.
        return (_id & TYPE_NF_BIT == TYPE_NF_BIT) && (_id & NF_INDEX_MASK == 0);
    }
    function isNonFungibleItem(uint256 _id) public pure returns(bool) {
        // A base type has the NF bit but does has an index.
        return (_id & TYPE_NF_BIT == TYPE_NF_BIT) && (_id & NF_INDEX_MASK != 0);
    }
    function ownerOf(uint256 _id) public view returns (address) {
        return nfOwners[_id];
    }

    // override
    function safeTransferFrom(address _from, address _to, uint256 _id, uint256 _value, bytes calldata _data) external override {

        require(msg.sender == _from || isApprovedForAll[_from][msg.sender], "NOT_AUTHORIZED");

        if (isNonFungible(_id)) {
            require(nfOwners[_id] == _from);
            nfOwners[_id] = _to;
            // You could keep balance of NF type in base type id like so:
            // uint256 baseType = getNonFungibleBaseType(_id);
            // balances[baseType][_from] = balances[baseType][_from].sub(_value);
            // balances[baseType][_to]   = balances[baseType][_to].add(_value);
        } else {
            balanceOf[_from][_id] = balanceOf[_from][_id].sub(_value);
            balanceOf[_to][_id]   = balanceOf[_to][_id].add(_value);
        }

        _safeTransferFrom(_from, _to, _id, _value, _data);
    }

    // override
    function safeBatchTransferFrom(address _from, address _to, uint256[] calldata _ids, uint256[] calldata _values, bytes calldata _data) external override {

        require(_ids.length == _values.length, "Array length must match");

        // Only supporting a global operator approval allows us to do only 1 check and not to touch storage to handle allowances.
        require(msg.sender == _from || isApprovedForAll[_from][msg.sender], "NOT_AUTHORIZED");

        // Cache value to local variable to reduce read costs.
        uint256 id;
        uint256 value;

        for (uint256 i = 0; i < _ids.length; ++i) {
            id = _ids[i];
            value = _values[i];

            if (isNonFungible(id)) {
                require(nfOwners[id] == _from);
                nfOwners[id] = _to;
            } else {
                balanceOf[_from][id] = balanceOf[_from][id].sub(value);
                balanceOf[_to][id]   = value.add(balanceOf[_to][id]);
            }
        }

        _safeBatchTransferFrom(_from, _to, _ids, _values, _data);
    }

    function balanceOf(address _owner, uint256 _id) external view override returns (uint256) {
        if (isNonFungibleItem(_id))
            return nfOwners[_id] == _owner ? 1 : 0;
        return balances[_owner][_id];
    }

    function balanceOfBatch(address[] calldata _owners, uint256[] calldata _ids) external view override returns (uint256[] memory) {

        require(_owners.length == _ids.length);

        uint256[] memory balances_ = new uint256[](_owners.length);

        for (uint256 i = 0; i < _owners.length; ++i) {
            uint256 id = _ids[i];
            if (isNonFungibleItem(id)) {
                balances_[i] = nfOwners[id] == _owners[i] ? 1 : 0;
            } else {
            	balances_[i] = balanceOf[_owners[i]][id];
            }
        }

        return balances_;
    }
}