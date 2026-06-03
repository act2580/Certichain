const { ethers } = require("hardhat");

async function main() {
  console.log("==============================================================");
  console.log("🎓 CERTICHAIN - DİPLOMA DOĞRULAMA SİMÜLASYONU BAŞLIYOR 🎓");
  console.log("==============================================================\n");

  // 1. Cüzdanları Ayarlayalım (Oyuncular)
  const [owner, university, student, employer] = await ethers.getSigners();
  
  console.log("👥 AKTÖRLER BELİRLENDİ:");
  console.log(`🏛️  Sistem Kurucusu (YÖK) : ${owner.address.slice(0,6)}...`);
  console.log(`🏫 Yetkili Üniversite  : ${university.address.slice(0,6)}...`);
  console.log(`🎓 Mezun Öğrenci      : ${student.address.slice(0,6)}...`);
  console.log(`🏢 İşveren / Doğrulayıcı: ${employer.address.slice(0,6)}...\n`);

  // 2. Blokzincir Üzerine Sözleşmeler Sözde Yükleniyor (Deploy)
  console.log("⚙️  Akıllı Sözleşmeler Ağa Yükleniyor...");
  const InstitutionRegistry = await ethers.getContractFactory("InstitutionRegistry");
  const iRegistry = await InstitutionRegistry.deploy();

  const CertificateRegistry = await ethers.getContractFactory("CertificateRegistry");
  const cRegistry = await CertificateRegistry.deploy(await iRegistry.getAddress());

  const SoulboundToken = await ethers.getContractFactory("SoulboundToken");
  const sToken = await SoulboundToken.deploy(await iRegistry.getAddress());
  
  console.log("✅ Sözleşmeler Yüklendi!\n");

  // ========================================================================= //
  
  console.log("----- [ ADIM 1: ÜNİVERSİTE YETKİLENDİRME ] -----");
  await iRegistry.connect(owner).addInstitution(university.address, "Atatürk Üniversitesi", "TR");
  console.log(`🏫 YÖK, "Atatürk Üniversitesi"ni sisteme KULLANICI olarak yetkilendirdi.\n`);

  // ========================================================================= //

  console.log("----- [ ADIM 2: DİPLOMA ÜRETİMİ VE HASH OLUŞTURMA ] -----");
  // Öğrencinin diploamsındaki veriler (TC Kimlik, Not Ortalaması vs) Backend'de birleştirilir
  const diplomaJSON = {
      adSoyad: "Ismail",
      bolum: "Yazilim Muhendisligi",
      derece: "Lisans",
      mezuniyetTarihi: "2026-06-15",
      universite: "Atatürk Üniversitesi"
  };
  
  // Bu verinin SHA-256 arka planda Hash'i alınır
  console.log("📄 Öğrencinin Diploma Verisi:", diplomaJSON);
  const jsonString = JSON.stringify(diplomaJSON);
  
  // Ethers.js içindeki keccak256(UTF8) bytes32'ye en yakın pratik örneğimizdir.
  // Projede sha-256 dendiği için sha256 simüle ediyoruz.
  const verininOzetHashi = ethers.sha256(ethers.toUtf8Bytes(jsonString));
  console.log(`🔏 Gizli ve Eşsiz Diploma Kısa Özeti (HASH): \n${verininOzetHashi}\n`);

  // ========================================================================= //

  console.log("----- [ ADIM 3: BLOKZİNCİRE KAYIT VE TOKEN (SBT) TESLİMATI ] -----");
  // A. Hash'i Registry'e yazıyoruz (QR okutulunca veritabanı olarak burdan eşleşecek)
  await cRegistry.connect(university).issueCertificate(verininOzetHashi, "DIPLOMA", 0, "");
  console.log("🔗 Üniversite, diploma HASH'ini blokzincire başarıyla ve değiştirilemez şekilde KAYDETTİ.");

  // B. SBT Token'ı öğrencinin mobil uygulamadaki cüzdanına gönderiyoruz
  await sToken.connect(university).issue(student.address, verininOzetHashi, "ipfs://mezun-metadata");
  console.log("🏆 Öğrencinin cüzdan hesabına diploması (Devredilemez Soulbound Token) GÖNDERİLDİ!\n");

  // ========================================================================= //

  console.log("----- [ ADIM 4: İŞVEREN QR KOD OKUTARAK DOĞRULAMA YAPIYOR ] -----");
  console.log(`🏢 İşveren, İsmail'in telefonundaki QR Kodu okutur...`);
  console.log(`🏢 QR Kod işverene HASH kodunu iletiyor: ${verininOzetHashi}`);
  
  const [gecerliMi, durum, kurumAdresi, verilmeZamani, bitisZamani] = await cRegistry.connect(employer).verifyCertificate(verininOzetHashi);
  
  if(gecerliMi) {
      console.log(`\n🎉 SONUÇ: ONAYLANDI!`);
      
      // Hangi kurum basmış? System'den bakalım:
      const kurumBilgisi = await iRegistry.getInstitution(kurumAdresi);
      
      console.log(`✅ Bu belge GERÇEK ve GEÇERLİ.`);
      console.log(`✅ Basan Kurum: ${kurumBilgisi.name} (${kurumBilgisi.country})`);
      
      // Öğrencide token var mı diye emin olalım
      const ogrenciTokenleri = await sToken.tokensOf(student.address);
      if(ogrenciTokenleri.length > 0) {
          console.log(`✅ İsmail'in dijital kimliğinde diploma (Soulbound Token) mevcut: Güven Onaylandı!\n`);
      }
  } else {
      console.log(`\n🚨 SONUÇ: GEÇERSİZ / SAHTE BELGE!\n`);
  }

  console.log("==============================================================");
  console.log("🎓 SİMÜLASYON TAMAMLANDI");
  console.log("==============================================================\n");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
