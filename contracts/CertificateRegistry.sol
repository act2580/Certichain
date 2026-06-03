// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./InstitutionRegistry.sol";

/**
 * @title CertificateRegistry
 * @author CertiChain Team
 * @notice Diploma ve sertifika verilerinin SHA-256 hash'lerini blokzincire kaydeder
 *         ve doğrulama sorgularını yönetir.
 *
 * @dev Sadece InstitutionRegistry'de kayıtlı aktif kurumlar hash yazabilir.
 *      Kişisel veri blokzincire yazılmaz — sadece verinin kriptografik özeti.
 */
contract CertificateRegistry is Ownable, Pausable {

    // ─── Veri Yapıları ─────────────────────────────────────────────────────

    enum CertificateStatus {
        Active,   // 0 - Geçerli
        Revoked   // 1 - İptal edildi
    }

    struct Certificate {
        bytes32             certHash;       // SHA-256 hash (off-chain'den gelir)
        address             issuer;         // Kaydeden kurum adresi
        uint256             issuedAt;       // Blokzincire yazılma zamanı
        uint256             expiresAt;      // Son geçerlilik (0 = süresiz)
        CertificateStatus   status;         // Durum
        string              certType;       // "DIPLOMA" | "CERTIFICATE" | "MICRO"
        string              metadataURI;    // IPFS veya kurum URL'i (opsiyonel)
    }

    // ─── State Değişkenleri ────────────────────────────────────────────────

    InstitutionRegistry private immutable _registry;

    // certHash => Certificate
    mapping(bytes32 => Certificate) private _certificates;

    // issuer address => kaydettiği hash listesi
    mapping(address => bytes32[]) private _institutionCerts;

    // Toplam kaydedilen sertifika sayısı
    uint256 private _totalCertificates;

    // ─── Olaylar (Events) ──────────────────────────────────────────────────

    event CertificateIssued(
        bytes32 indexed certHash,
        address indexed issuer,
        string  certType,
        uint256 issuedAt,
        uint256 expiresAt
    );

    event CertificateRevoked(
        bytes32 indexed certHash,
        address indexed revokedBy,
        uint256 revokedAt
    );

    event MetadataUpdated(
        bytes32 indexed certHash,
        string  newMetadataURI
    );

    // ─── Modifier'lar ──────────────────────────────────────────────────────

    modifier onlyActiveInstitution() {
        require(
            _registry.isActiveInstitution(msg.sender),
            "CertificateRegistry: Yetkisiz kurum"
        );
        _;
    }

    modifier certExists(bytes32 certHash) {
        require(
            _certificates[certHash].issuedAt != 0,
            "CertificateRegistry: Sertifika bulunamadi"
        );
        _;
    }

    modifier onlyIssuer(bytes32 certHash) {
        require(
            _certificates[certHash].issuer == msg.sender,
            "CertificateRegistry: Sadece kayit eden kurum bu islemi yapabilir"
        );
        _;
    }

    // ─── Constructor ───────────────────────────────────────────────────────

    /**
     * @param registryAddr_ Daha önce deploy edilmiş InstitutionRegistry adresi
     */
    constructor(address registryAddr_) Ownable(msg.sender) {
        require(registryAddr_ != address(0), "CertificateRegistry: Gecersiz registry adresi");
        _registry = InstitutionRegistry(registryAddr_);
    }

    // ─── Yazma Fonksiyonları ───────────────────────────────────────────────

    /**
     * @notice Bir sertifikanın hash'ini blokzincire kaydeder.
     * @param certHash    Diploma/sertifika verisinin SHA-256 hash'i (bytes32)
     * @param certType    Sertifika türü: "DIPLOMA", "CERTIFICATE", "MICRO"
     * @param expiresAt   Son geçerlilik tarihi (Unix timestamp). 0 = süresiz
     * @param metadataURI IPFS CID veya kurum URL'i (boş bırakılabilir)
     *
     * @dev certHash, off-chain tarafta şu şekilde üretilmeli:
     *      keccak256(sha256(diplomaJSON)) veya direkt sha256(diplomaJSON)
     *      Backend bunu bytes32 olarak gönderir.
     */
    function issueCertificate(
        bytes32       certHash,
        string calldata certType,
        uint256       expiresAt,
        string calldata metadataURI
    )
        external
        whenNotPaused
        onlyActiveInstitution
    {
        require(certHash != bytes32(0),               "CertificateRegistry: Hash bos olamaz");
        require(_certificates[certHash].issuedAt == 0, "CertificateRegistry: Bu hash zaten kayitli");
        require(
            expiresAt == 0 || expiresAt > block.timestamp,
            "CertificateRegistry: Gecmis bir tarih girilemez"
        );
        require(bytes(certType).length > 0,           "CertificateRegistry: Sertifika turu bos olamaz");

        _certificates[certHash] = Certificate({
            certHash:    certHash,
            issuer:      msg.sender,
            issuedAt:    block.timestamp,
            expiresAt:   expiresAt,
            status:      CertificateStatus.Active,
            certType:    certType,
            metadataURI: metadataURI
        });

        _institutionCerts[msg.sender].push(certHash);
        _totalCertificates++;

        emit CertificateIssued(certHash, msg.sender, certType, block.timestamp, expiresAt);
    }

    /**
     * @notice Birden fazla sertifikayı tek işlemde kaydeder (toplu kayıt).
     *         Gas tasarrufu için kullanılır.
     */
    function issueBatch(
        bytes32[]       calldata certHashes,
        string calldata certType,
        uint256         expiresAt,
        string calldata metadataURI
    )
        external
        whenNotPaused
        onlyActiveInstitution
    {
        require(certHashes.length > 0,   "CertificateRegistry: Bos liste");
        require(certHashes.length <= 100, "CertificateRegistry: Maksimum 100 kayit");

        for (uint256 i = 0; i < certHashes.length; i++) {
            bytes32 h = certHashes[i];
            require(h != bytes32(0),                   "CertificateRegistry: Hash bos olamaz");
            require(_certificates[h].issuedAt == 0,    "CertificateRegistry: Hash zaten kayitli");

            _certificates[h] = Certificate({
                certHash:    h,
                issuer:      msg.sender,
                issuedAt:    block.timestamp,
                expiresAt:   expiresAt,
                status:      CertificateStatus.Active,
                certType:    certType,
                metadataURI: metadataURI
            });

            _institutionCerts[msg.sender].push(h);
            emit CertificateIssued(h, msg.sender, certType, block.timestamp, expiresAt);
        }

        _totalCertificates += certHashes.length;
    }

    /**
     * @notice Bir sertifikayı iptal eder.
     *         Sadece kaydeden kurum iptal edebilir.
     */
    function revokeCertificate(bytes32 certHash)
        external
        whenNotPaused
        certExists(certHash)
        onlyIssuer(certHash)
    {
        require(
            _certificates[certHash].status == CertificateStatus.Active,
            "CertificateRegistry: Sertifika zaten iptal edilmis"
        );
        _certificates[certHash].status = CertificateStatus.Revoked;
        emit CertificateRevoked(certHash, msg.sender, block.timestamp);
    }

    /**
     * @notice Metadata URI'sini günceller (IPFS pinleme değişikliği gibi).
     */
    function updateMetadata(bytes32 certHash, string calldata newMetadataURI)
        external
        certExists(certHash)
        onlyIssuer(certHash)
    {
        _certificates[certHash].metadataURI = newMetadataURI;
        emit MetadataUpdated(certHash, newMetadataURI);
    }

    // ─── Doğrulama Fonksiyonları ───────────────────────────────────────────

    /**
     * @notice Bir hash'in geçerli olup olmadığını doğrular.
     * @return valid     true = geçerli, false = geçersiz/bulunamadı/iptal
     * @return status    Sertifika durumu (Active / Revoked)
     * @return issuer    Kaydeden kurumun adresi
     * @return issuedAt  Kayıt zamanı
     * @return expiresAt Son geçerlilik zamanı (0 = süresiz)
     */
    function verifyCertificate(bytes32 certHash)
        external
        view
        returns (
            bool              valid,
            CertificateStatus status,
            address           issuer,
            uint256           issuedAt,
            uint256           expiresAt
        )
    {
        Certificate storage cert = _certificates[certHash];

        if (cert.issuedAt == 0) {
            // Hiç kaydedilmemiş
            return (false, CertificateStatus.Revoked, address(0), 0, 0);
        }

        bool notRevoked = cert.status == CertificateStatus.Active;
        bool notExpired = cert.expiresAt == 0 || cert.expiresAt > block.timestamp;

        return (
            notRevoked && notExpired,
            cert.status,
            cert.issuer,
            cert.issuedAt,
            cert.expiresAt
        );
    }

    /**
     * @notice Bir sertifikanın tüm detaylarını döner.
     */
    function getCertificate(bytes32 certHash)
        external
        view
        certExists(certHash)
        returns (Certificate memory)
    {
        return _certificates[certHash];
    }

    /**
     * @notice Bir kurumun kaydettiği tüm hash'lerin listesini döner.
     */
    function getInstitutionCertificates(address institution)
        external
        view
        returns (bytes32[] memory)
    {
        return _institutionCerts[institution];
    }

    /**
     * @notice Toplam kayıtlı sertifika sayısı.
     */
    function totalCertificates() external view returns (uint256) {
        return _totalCertificates;
    }

    /**
     * @notice Bağlı InstitutionRegistry adresi.
     */
    function registryAddress() external view returns (address) {
        return address(_registry);
    }

    // ─── Acil Durum (Owner) ────────────────────────────────────────────────

    /** @notice Sistemi durdurur (yeni kayıt/iptal işlemleri yapılamaz). */
    function pause() external onlyOwner {
        _pause();
    }

    /** @notice Sistemi devam ettirir. */
    function unpause() external onlyOwner {
        _unpause();
    }
}
