// contracts/GameItem.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

contract Vault is ERC721URIStorage {
	using SafeMath for uint256;

	uint256 vaultCount;

	event CreateVault(address creator, uint256 id);
	event DestroyVault(uint256 id);

    constructor(
		string memory name,
		string memory symbol
	) ERC721(name, symbol) {
		vaultCount = 0;
	}

	function _createVault(address to) internal returns(uint256) {
		uint256 id = vaultCount.add(1);

		assert(id > vaultCount);
		vaultCount = id;

		_safeMint(to, id);

		emit CreateVault(to, id);

		return(id);
	}

	function _destroyVault(uint256 tokenId) internal {
		_burn(tokenId);

		emit DestroyVault(tokenId);
	}
}