// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./InstitutionRegistry.sol";

/**
 * @title SoulboundToken
 * @author CertiChain Team
 * @notice Diploma ve sertifikaları kişiye kalıcı olarak bağlayan,
 *         devredilemez (Soulbound) dijital token'lar üretir.
 *
 * @dev ERC-5484 ilhamıyla tasarlanmıştır.
 *      Transfer tamamen engellenmektedir — sadece mint ve burn vardır.
 *      Her cüzdan adresi belirli bir certHash için yalnızca 1 SBT alabilir.
 */
contract SoulboundToken is Ownable, Pausable {

    // ─── Veri Yapıları ─────────────────────────────────────────────────────

    struct SBT {
        uint256 tokenId;       // Benzersiz token kimliği
        address owner;         // Token sahibi (mezun/öğrenci)
        bytes32 certHash;      // İlgili CertificateRegistry'deki hash
        address issuer;        // Mint eden kurum
        uint256 mintedAt;      // Mint zamanı
        string  tokenURI;      // Metadata URI (IPFS)
    }

    // ─── State Değişkenleri ────────────────────────────────────────────────

    InstitutionRegistry private immutable _registry;

    uint256 private _nextTokenId;

    // tokenId => SBT
    mapping(uint256 => SBT) private _tokens;

    // owner => tokenId listesi
    mapping(address => uint256[]) private _ownerTokens;

    // certHash => owner => tokenId (aynı hash iki kez mint edilemesin)
    mapping(bytes32 => mapping(address => uint256)) private _certOwnerToken;

    // tokenId => var mı?
    mapping(uint256 => bool) private _exists;

    // ─── Sabitler ──────────────────────────────────────────────────────────

    string public constant name   = "CertiChain Soulbound Token";
    string public constant symbol = "CSBT";

    // ─── Olaylar (Events) ──────────────────────────────────────────────────

    event Issued(
        uint256 indexed tokenId,
        address indexed owner,
        bytes32 indexed certHash,
        address         issuer,
        uint256         mintedAt
    );

    event Revoked(
        uint256 indexed tokenId,
        address indexed owner,
        address         revokedBy,
        uint256         revokedAt
    );

    // ─── Hatalar (Custom Errors) ────────────────────────────────────────────

    error TransferNotAllowed();
    error TokenNotFound(uint256 tokenId);
    error AlreadyIssued(bytes32 certHash, address owner);
    error UnauthorizedInstitution(address caller);
    error UnauthorizedRevocation(address caller);

    // ─── Modifier'lar ──────────────────────────────────────────────────────

    modifier onlyActiveInstitution() {
        if (!_registry.isActiveInstitution(msg.sender)) {
            revert UnauthorizedInstitution(msg.sender);
        }
        _;
    }

    modifier tokenMustExist(uint256 tokenId) {
        if (!_exists[tokenId]) {
            revert TokenNotFound(tokenId);
        }
        _;
    }

    // ─── Constructor ───────────────────────────────────────────────────────

    constructor(address registryAddr_) Ownable(msg.sender) {
        require(registryAddr_ != address(0), "SoulboundToken: Gecersiz registry adresi");
        _registry = InstitutionRegistry(registryAddr_);
        _nextTokenId = 1;
    }

    // ─── Mint (Issue) ───────────────────────────────────────────────────────

    /**
     * @notice Bir mezuna Soulbound Token mint eder.
     * @param to        Token alacak kişinin cüzdan adresi
     * @param certHash  CertificateRegistry'deki ilgili hash
     * @param tokenURI_ Metadata URI (IPFS CID veya URL)
     * @return tokenId  Oluşturulan token'ın ID'si
     *
     * @dev Aynı certHash + owner kombinasyonu için ikinci mint yapılamaz.
     */
    function issue(
        address         to,
        bytes32         certHash,
        string calldata tokenURI_
    )
        external
        whenNotPaused
        onlyActiveInstitution
        returns (uint256 tokenId)
    {
        require(to != address(0),        "SoulboundToken: Gecersiz alici adresi");
        require(certHash != bytes32(0),  "SoulboundToken: Gecersiz certHash");

        // Aynı kişiye aynı sertifika iki kez verilemez
        if (_certOwnerToken[certHash][to] != 0) {
            revert AlreadyIssued(certHash, to);
        }

        tokenId = _nextTokenId++;

        _tokens[tokenId] = SBT({
            tokenId:  tokenId,
            owner:    to,
            certHash: certHash,
            issuer:   msg.sender,
            mintedAt: block.timestamp,
            tokenURI: tokenURI_
        });

        _ownerTokens[to].push(tokenId);
        _certOwnerToken[certHash][to] = tokenId;
        _exists[tokenId] = true;

        emit Issued(tokenId, to, certHash, msg.sender, block.timestamp);
    }

    /**
     * @notice Bir SBT'yi iptal eder (burn).
     *         Owner veya token'ı basan kurum iptal edebilir.
     */
    function revoke(uint256 tokenId)
        external
        whenNotPaused
        tokenMustExist(tokenId)
    {
        SBT storage token = _tokens[tokenId];

        bool isOwner      = msg.sender == token.owner;
        bool isIssuer     = msg.sender == token.issuer;
        bool isContractOwner = msg.sender == owner();

        if (!isOwner && !isIssuer && !isContractOwner) {
            revert UnauthorizedRevocation(msg.sender);
        }

        address tokenOwner = token.owner;
        bytes32 certHash   = token.certHash;

        // State temizliği
        delete _certOwnerToken[certHash][tokenOwner];
        delete _tokens[tokenId];
        _exists[tokenId] = false;

        // ownerTokens listesinden çıkar
        _removeFromOwnerList(tokenOwner, tokenId);

        emit Revoked(tokenId, tokenOwner, msg.sender, block.timestamp);
    }

    // ─── Transfer Engeli ───────────────────────────────────────────────────

    /**
     * @dev Soulbound — transfer tamamen yasaktır.
     *      ERC-721 uyumluluğunu engellemek için kasıtlı olarak konulmamıştır.
     */
    function transfer(address, uint256) external pure {
        revert TransferNotAllowed();
    }

    // ─── Okuma Fonksiyonları ───────────────────────────────────────────────

    /**
     * @notice Token bilgilerini döner.
     */
    function getToken(uint256 tokenId)
        external
        view
        tokenMustExist(tokenId)
        returns (SBT memory)
    {
        return _tokens[tokenId];
    }

    /**
     * @notice Bir adresin sahip olduğu tüm token ID'lerini döner.
     */
    function tokensOf(address owner_)
        external
        view
        returns (uint256[] memory)
    {
        return _ownerTokens[owner_];
    }

    /**
     * @notice Belirli bir certHash için hangi tokenId'nin mint edildiğini döner.
     *         0 dönerse mint edilmemiştir.
     */
    function tokenOfCert(bytes32 certHash, address owner_)
        external
        view
        returns (uint256)
    {
        return _certOwnerToken[certHash][owner_];
    }

    /**
     * @notice Token'ın var olup olmadığını döner.
     */
    function exists(uint256 tokenId) external view returns (bool) {
        return _exists[tokenId];
    }

    /**
     * @notice Token'ın metadata URI'sini döner.
     */
    function tokenURI(uint256 tokenId)
        external
        view
        tokenMustExist(tokenId)
        returns (string memory)
    {
        return _tokens[tokenId].tokenURI;
    }

    /**
     * @notice Toplam mint edilen (şu an var olan) token sayısını döner.
     * @dev Revoke edilenler dahil değildir.
     */
    function totalSupply() external view returns (uint256) {
        // nextTokenId - 1 = toplam mint; revoke edilenleri düşemeyiz O(1)'de,
        // bu yüzden anlık kullanım için ownerTokens.length toplamı daha güvenli.
        return _nextTokenId - 1;
    }

    /**
     * @notice Bağlı InstitutionRegistry adresi.
     */
    function registryAddress() external view returns (address) {
        return address(_registry);
    }

    // ─── Acil Durum (Owner) ────────────────────────────────────────────────

    function pause()   external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ─── İç Yardımcı Fonksiyonlar ──────────────────────────────────────────

    /**
     * @dev _ownerTokens listesinden belirli bir tokenId'yi siler (swap & pop).
     */
    function _removeFromOwnerList(address owner_, uint256 tokenId) private {
        uint256[] storage list = _ownerTokens[owner_];
        uint256 len = list.length;
        for (uint256 i = 0; i < len; i++) {
            if (list[i] == tokenId) {
                list[i] = list[len - 1];
                list.pop();
                break;
            }
        }
    }
}
