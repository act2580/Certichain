const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("CertiChain", function () {
  let InstitutionRegistry, institutionRegistry;
  let CertificateRegistry, certificateRegistry;
  let SoulboundToken, soulboundToken;
  let owner, university, student, unauthorizedUser;

  // Örnek Test Verileri
  const univName = "Ataturk Universitesi";
  const univCountry = "TR";
  const dummyCertHash = ethers.zeroPadValue(ethers.hexlify(ethers.toUtf8Bytes("diploma-hash-123")), 32);
  const dummyCertType = "DIPLOMA";
  const dummyMetadataURI = "ipfs://QmYwAPJzv5CZsnA625s3Xf2sm5DcgXU1G4xAqc9zT2heMU";

  beforeEach(async function () {
    // 1. Hesapları (Cüzdanları) Ayarla
    [owner, university, student, unauthorizedUser] = await ethers.getSigners();

    // 2. Sözleşmeleri Dağıt (Lokal Ağda)
    InstitutionRegistry = await ethers.getContractFactory("InstitutionRegistry");
    institutionRegistry = await InstitutionRegistry.deploy();

    CertificateRegistry = await ethers.getContractFactory("CertificateRegistry");
    certificateRegistry = await CertificateRegistry.deploy(await institutionRegistry.getAddress());

    SoulboundToken = await ethers.getContractFactory("SoulboundToken");
    soulboundToken = await SoulboundToken.deploy(await institutionRegistry.getAddress());
  });

  describe("1. Kurum Yönetimi (Institution Registry)", function () {
    it("Sahip (Owner) yeni bir egitim kurumu ekleyebilmeli", async function () {
      await expect(institutionRegistry.addInstitution(university.address, univName, univCountry))
        .to.emit(institutionRegistry, "InstitutionAdded")
        .withArgs(university.address, univName, univCountry, (any) => true); // Timestamp kontrolünü es geçiyoruz

      const isActive = await institutionRegistry.isActiveInstitution(university.address);
      expect(isActive).to.be.true;
    });

    it("Yetkisiz kisiler (Sahip olmayan) kurum ekleyememeli", async function () {
      await expect(
        institutionRegistry.connect(unauthorizedUser).addInstitution(university.address, univName, univCountry)
      ).to.be.revertedWithCustomError(institutionRegistry, "OwnableUnauthorizedAccount");
    });
  });

  describe("2. Sertifika Kaydi & Dogrulanmasi (Certificate Registry)", function () {
    beforeEach(async function () {
      // Her testten önce "university" cüzdanını aktif bir kurum olarak ekleyelim
      await institutionRegistry.addInstitution(university.address, univName, univCountry);
    });

    it("Kayitli bir kurum basariyla sertifika tescil edebilmeli", async function () {
      await expect(
        certificateRegistry.connect(university).issueCertificate(dummyCertHash, dummyCertType, 0, dummyMetadataURI)
      )
        .to.emit(certificateRegistry, "CertificateIssued")
        .withArgs(dummyCertHash, university.address, dummyCertType, (any) => true, 0);

      // Doğrulayalım
      const [isValid, status, issuer, issuedAt, expiresAt] = await certificateRegistry.verifyCertificate(dummyCertHash);
      expect(isValid).to.be.true;
      expect(status).to.equal(0); // 0 = Active
      expect(issuer).to.equal(university.address);
    });

    it("Kayitsiz bir kisi ya da kurum sertifika kaydedememeli", async function () {
      await expect(
        certificateRegistry.connect(unauthorizedUser).issueCertificate(dummyCertHash, dummyCertType, 0, dummyMetadataURI)
      ).to.be.revertedWith("CertificateRegistry: Yetkisiz kurum");
    });
  });

  describe("3. Soulbound Token (SBT)", function () {
    beforeEach(async function () {
      await institutionRegistry.addInstitution(university.address, univName, univCountry);
    });

    it("Ogrenciye SBT diploma basariyla Mint edilebilmeli", async function () {
      const tx = await soulboundToken.connect(university).issue(student.address, dummyCertHash, dummyMetadataURI);
      const receipt = await tx.wait(); // eventleri okumak için bekle

      const hasSBT = await soulboundToken.tokensOf(student.address);
      expect(hasSBT.length).to.equal(1);

      const tokenId = hasSBT[0];
      const sbtDetails = await soulboundToken.getToken(tokenId);
      expect(sbtDetails.owner).to.equal(student.address);
      expect(sbtDetails.certHash).to.equal(dummyCertHash);
    });

    it("Token baska bir cuzdan adresine asla transfer EDILEMEMELI (Soulbound ozelligi)", async function () {
       // Önce öğrenciye token'ı ver
       await soulboundToken.connect(university).issue(student.address, dummyCertHash, dummyMetadataURI);
       const tokens = await soulboundToken.tokensOf(student.address);
       const tokenId = tokens[0];

       // Öğrenci bu token'ı satıp ya da devredebilir mi?
       await expect(
         soulboundToken.connect(student).transfer(unauthorizedUser.address, tokenId)
       ).to.be.revertedWithCustomError(soulboundToken, "TransferNotAllowed");
    });
    
    it("Ayni ogrenciye ayni ders/diploma 2 kez verilememeli", async function () {
        await soulboundToken.connect(university).issue(student.address, dummyCertHash, dummyMetadataURI);
        
        await expect(
          soulboundToken.connect(university).issue(student.address, dummyCertHash, dummyMetadataURI)
        ).to.be.revertedWithCustomError(soulboundToken, "AlreadyIssued");
     });
  });
});
