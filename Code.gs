/**
 * ==============================================================================
 * GOOGLE APPS SCRIPT: UPLOAD FOTO OPERASIONAL KE GOOGLE DRIVE & SPREADSHEET
 * SE MANAGEMENT JOB - MINE OPERATIONS (LUBETRUCK & WATER TRUCK)
 * ==============================================================================
 * Target Spreadsheet : https://docs.google.com/spreadsheets/d/1zoDx6VZQkfwZ_rZ97qV3d-WVYC8KGBC7RN0c8aLQRSY/edit?gid=0#gid=0
 * Spreadsheet ID     : 1zoDx6VZQkfwZ_rZ97qV3d-WVYC8KGBC7RN0c8aLQRSY
 * Target Folder ID   : 11EQ_NsZYeMmEKURpibXCRtyrQw5kKkh3 (Fallback otomatis ke folder tempat Spreadsheet berada)
 *
 * PANDUAN DEPLOY SEBAGAI WEB APP DI SPREADSHEET INI:
 * ------------------------------------------------------------------------------
 * 1. Di Google Spreadsheet Anda (https://docs.google.com/spreadsheets/d/1zoDx6VZQkfwZ_rZ97qV3d-WVYC8KGBC7RN0c8aLQRSY),
 *    klik menu "Ekstensi" (Extensions) -> pilih "Apps Script".
 * 2. Hapus semua kode lama di editor Apps Script, lalu salin dan tempelkan seluruh isi file Code.gs ini.
 * 3. Klik tombol Simpan (ikon disket 💾 atau Ctrl+S).
 * 4. Klik tombol biru "Deploy" (Terapkan) di pojok kanan atas -> pilih "New deployment" (Deployment baru).
 *    *(Jika sudah pernah deploy sebelumnya, pilih "Manage deployments" -> klik ikon pensil ✏️ -> pilih Version: "New version")*
 * 5. Klik ikon roda gigi ⚙️ di sebelah "Select type" -> pilih "Web app".
 * 6. Atur konfigurasi wajib berikut:
 *    - Description   : SE Management Job Photo Upload API v2
 *    - Execute as    : Me (email Google akun Anda)
 *    - Who has access: Anyone (Siapa saja)  <-- WAJIB: agar web app bisa upload foto tanpa login
 * 7. Klik tombol "Deploy", lalu klik "Authorize access" dan berikan izin akses Google Drive & Spreadsheet.
 * 8. Salin "Web app URL" yang muncul (URL berakhiran /exec).
 * 9. Tempelkan URL tersebut ke web: buka menu Pengaturan Profil (Ikon Gir/Profil di web) ->
 *    masukkan URL pada kolom "Upload Foto Google Drive" -> klik "Simpan URL" dan "Tes Koneksi".
 * ==============================================================================
 */

// ID Google Spreadsheet Target (Sesuai dengan spreadsheet yang Anda gunakan)
const SPREADSHEET_ID = '1zoDx6VZQkfwZ_rZ97qV3d-WVYC8KGBC7RN0c8aLQRSY';

// ID Folder Google Drive Tujuan (Jika tidak dapat diakses, otomatis menyimpan di folder yang sama dengan Spreadsheet)
const TARGET_FOLDER_ID = '11EQ_NsZYeMmEKURpibXCRtyrQw5kKkh3';

// Nama Tab Sheet untuk Log Riwayat Foto
const SHEET_TAB_NAME = 'Log Foto Operasional';

/**
 * ==============================================================================
 * ENDPOINT UTAMA POST: Menerima unggahan foto dari aplikasi Web (index.html)
 * ==============================================================================
 */
function doPost(e) {
  // Pengaman jika fungsi dijalankan manual dari editor Apps Script tanpa event parameter 'e'
  if (!e || (!e.postData && !e.parameter)) {
    Logger.log('ℹ️ doPost dijalankan secara manual dari editor. Mengalihkan ke fungsi testUploadFoto()...');
    return testUploadFoto();
  }

  try {
    let payload = {};

    if (e.postData && e.postData.contents) {
      try {
        payload = JSON.parse(e.postData.contents);
      } catch (err) {
        payload = e.parameter || {};
      }
    } else if (e.parameter) {
      payload = e.parameter;
    }

    const result = processUploadAndSave(payload);
    return createJsonResponse(result);

  } catch (error) {
    Logger.log('❌ Error pada doPost: ' + error.toString());
    return createJsonResponse({
      status: 'error',
      message: 'Gagal memproses unggahan: ' + error.toString()
    });
  }
}

/**
 * ==============================================================================
 * ENDPOINT GET: Health Check & Tes Koneksi dari Web
 * ==============================================================================
 */
function doGet(e) {
  try {
    const ss = getTargetSpreadsheet();
    const folder = getTargetFolder(ss);

    return createJsonResponse({
      status: 'ok',
      service: 'SE Management Job - Google Drive & Spreadsheet Photo Upload API v2',
      spreadsheetId: SPREADSHEET_ID,
      spreadsheetName: ss ? ss.getName() : 'Google Spreadsheet Terhubung',
      spreadsheetUrl: ss ? ss.getUrl() : ('https://docs.google.com/spreadsheets/d/' + SPREADSHEET_ID + '/edit'),
      folderId: folder.getId(),
      folderName: folder.getName(),
      folderUrl: folder.getUrl(),
      timestamp: new Date().toISOString()
    });
  } catch (err) {
    return createJsonResponse({
      status: 'error',
      message: 'Koneksi error: ' + err.toString(),
      spreadsheetId: SPREADSHEET_ID,
      folderId: TARGET_FOLDER_ID
    });
  }
}

/**
 * ==============================================================================
 * LOGIKA UTAMA: Simpan Berkas ke Drive & Catat Entri ke Google Spreadsheet
 * ==============================================================================
 */
function processUploadAndSave(payload) {
  const base64Data = payload.base64 || payload.data || payload.image;
  if (!base64Data) {
    return {
      status: 'error',
      message: 'Data base64 foto wajib disertakan!'
    };
  }

  // Ekstrak MIME Type dan data Base64 murni
  let mimeType = 'image/jpeg';
  let cleanBase64 = base64Data;

  if (base64Data.indexOf('data:') === 0 && base64Data.indexOf(';base64,') !== -1) {
    const parts = base64Data.split(';base64,');
    mimeType = parts[0].replace('data:', '');
    cleanBase64 = parts[1];
  } else if (payload.mimeType) {
    mimeType = payload.mimeType;
  }

  // Bersihkan & susun nama file
  const unitNo = (payload.unit || payload.noLambung || 'UNIT').replace(/[^a-zA-Z0-9_-]/g, '');
  const category = (payload.category || payload.jobType || 'ACH').replace(/[^a-zA-Z0-9_-]/g, '');
  const slotIdx = payload.slot || '1';
  const timestamp = Utilities.formatDate(new Date(), 'Asia/Makassar', 'yyyyMMdd_HHmmss');
  const randomSuffix = Math.floor(1000 + Math.random() * 9000);
  const ext = mimeType.indexOf('png') !== -1 ? 'png' : 'jpg';

  const fileName = payload.filename || (category + '_' + unitNo + '_S' + slotIdx + '_' + timestamp + '_' + randomSuffix + '.' + ext);

  // Decode binary data & buat Blob gambar
  const decodedBytes = Utilities.base64Decode(cleanBase64);
  const blob = Utilities.newBlob(decodedBytes, mimeType, fileName);

  // Dapatkan target folder (folder ID khusus atau folder tempat spreadsheet berada)
  const ss = getTargetSpreadsheet();
  const targetFolder = getTargetFolder(ss);

  // Simpan berkas gambar ke Drive
  const createdFile = targetFolder.createFile(blob);

  // Set izin akses publik siap pakai agar gambar langsung tampil di web
  try {
    createdFile.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
  } catch (permErr) {
    Logger.log('Peringatan saat set sharing permission: ' + permErr.toString());
  }

  const fileId = createdFile.getId();
  const directImageUrl = 'https://lh3.googleusercontent.com/d/' + fileId;
  const driveThumbnailUrl = 'https://drive.google.com/thumbnail?id=' + fileId + '&sz=w1000';
  const driveViewUrl = createdFile.getUrl();
  const driveDownloadUrl = 'https://drive.google.com/uc?export=view&id=' + fileId;

  // Catat riwayat unggahan ke Google Spreadsheet target
  let spreadsheetUrl = '';
  try {
    if (ss) {
      spreadsheetUrl = ss.getUrl();
      appendLogRow(ss, {
        unit: unitNo,
        category: category,
        slot: slotIdx,
        jobId: payload.jobId || '-',
        fileName: fileName,
        fileId: fileId,
        directUrl: directImageUrl,
        driveViewUrl: driveViewUrl
      });
    }
  } catch (sheetErr) {
    Logger.log('Peringatan saat mencatat ke Spreadsheet (tidak menghentikan proses): ' + sheetErr.toString());
  }

  return {
    status: 'success',
    message: 'Foto berhasil disimpan ke Google Drive dan dicatat di Spreadsheet!',
    fileId: fileId,
    fileName: fileName,
    url: directImageUrl,          // URL utama untuk <img src="...">
    directUrl: directImageUrl,
    thumbnailUrl: driveThumbnailUrl,
    driveViewUrl: driveViewUrl,
    driveDownloadUrl: driveDownloadUrl,
    spreadsheetUrl: spreadsheetUrl || ('https://docs.google.com/spreadsheets/d/' + SPREADSHEET_ID + '/edit'),
    folderId: targetFolder.getId(),
    folderName: targetFolder.getName(),
    uploadedAt: new Date().toISOString()
  };
}

/**
 * ==============================================================================
 * HELPER SPREADSHEET: Ambil Spreadsheet Aktif atau Buka Berdasarkan ID
 * ==============================================================================
 */
function getTargetSpreadsheet() {
  try {
    const active = SpreadsheetApp.getActiveSpreadsheet();
    if (active) return active;
  } catch (e) {}

  try {
    return SpreadsheetApp.openById(SPREADSHEET_ID);
  } catch (err) {
    Logger.log('Gagal membuka spreadsheet ID ' + SPREADSHEET_ID + ': ' + err.toString());
    return null;
  }
}

/**
 * ==============================================================================
 * HELPER FOLDER: Ambil Folder Google Drive Tujuan
 * (Folder ID Khusus -> Folder Induk Spreadsheet -> Root Drive)
 * ==============================================================================
 */
function getTargetFolder(ss) {
  // 1. Coba Folder ID spesifik
  try {
    if (TARGET_FOLDER_ID && TARGET_FOLDER_ID.trim() !== '') {
      return DriveApp.getFolderById(TARGET_FOLDER_ID);
    }
  } catch (e) {
    Logger.log('Folder ID spesifik tidak ditemukan/error: ' + e.toString());
  }

  // 2. Jika gagal atau belum disetel, gunakan folder tempat Spreadsheet berada
  try {
    if (ss) {
      const ssFile = DriveApp.getFileById(ss.getId());
      const parents = ssFile.getParents();
      if (parents.hasNext()) {
        return parents.next();
      }
    }
  } catch (e) {
    Logger.log('Gagal mendapatkan folder induk spreadsheet: ' + e.toString());
  }

  // 3. Fallback terakhir ke Root Drive
  return DriveApp.getRootFolder();
}

/**
 * ==============================================================================
 * HELPER SHEET: Ambil atau Inisialisasi Sheet Tab Log di dalam Spreadsheet
 * ==============================================================================
 */
function getOrCreateLogSheet(spreadsheet) {
  if (!spreadsheet) return null;

  let sheet = spreadsheet.getSheetByName(SHEET_TAB_NAME);

  if (!sheet) {
    // Periksa apakah sheet pertama kosong sehingga bisa langsung digunakan
    const sheets = spreadsheet.getSheets();
    if (sheets.length > 0 && sheets[0].getLastRow() <= 1 && sheets[0].getLastColumn() <= 1) {
      sheet = sheets[0];
      sheet.setName(SHEET_TAB_NAME);
    } else {
      // Buat tab sheet baru
      sheet = spreadsheet.insertSheet(SHEET_TAB_NAME);
    }

    // Format Baris Header
    sheet.appendRow([
      'No',
      'Waktu Upload (WITA)',
      'No Unit / Lambung',
      'Kategori Pekerjaan',
      'Slot Foto',
      'Job ID',
      'Nama File',
      'ID File Google Drive',
      'Pratinjau Foto',
      'Direct URL Gambar',
      'Link Buka di Google Drive',
      'Status'
    ]);

    // Beri gaya header yang elegan (Warna Hijau Tambang & Teks Bold)
    const headerRange = sheet.getRange(1, 1, 1, 12);
    headerRange.setBackground('#059669');
    headerRange.setFontColor('#FFFFFF');
    headerRange.setFontWeight('bold');
    headerRange.setHorizontalAlignment('center');
    sheet.setFrozenRows(1);

    // Atur lebar kolom yang nyaman
    try {
      sheet.setColumnWidth(1, 50);   // No
      sheet.setColumnWidth(2, 150);  // Waktu
      sheet.setColumnWidth(3, 110);  // Unit
      sheet.setColumnWidth(4, 130);  // Kategori
      sheet.setColumnWidth(5, 80);   // Slot
      sheet.setColumnWidth(6, 120);  // Job ID
      sheet.setColumnWidth(7, 220);  // Nama File
      sheet.setColumnWidth(8, 220);  // File ID
      sheet.setColumnWidth(9, 100);  // Pratinjau
      sheet.setColumnWidth(10, 250); // Direct URL
      sheet.setColumnWidth(11, 200); // Drive Link
      sheet.setColumnWidth(12, 80);  // Status
    } catch (cwErr) {}
  }

  return sheet;
}

/**
 * ==============================================================================
 * HELPER ROW: Tambahkan Baris Data Baru ke Spreadsheet
 * ==============================================================================
 */
function appendLogRow(spreadsheet, info) {
  if (!spreadsheet) return;
  const sheet = getOrCreateLogSheet(spreadsheet);
  if (!sheet) return;

  const lastRow = sheet.getLastRow();
  const noUrut = Math.max(1, lastRow); // Baris 1 adalah header
  const waktuStr = Utilities.formatDate(new Date(), 'Asia/Makassar', 'dd/MM/yyyy HH:mm:ss');

  // Formula IMAGE untuk menampilkan pratinjau thumbnail langsung di sel spreadsheet
  const imageFormula = '=IMAGE("' + info.directUrl + '")';

  sheet.appendRow([
    noUrut,
    waktuStr,
    info.unit,
    info.category,
    'Foto ' + info.slot,
    info.jobId,
    info.fileName,
    info.fileId,
    imageFormula,
    info.directUrl,
    info.driveViewUrl,
    'SUKSES'
  ]);

  try {
    sheet.setRowHeight(sheet.getLastRow(), 50);
  } catch (e) {}
}

/**
 * ==============================================================================
 * HELPER OUTPUT: Format Output JSON
 * ==============================================================================
 */
function createJsonResponse(dataObject) {
  const output = ContentService.createTextOutput(JSON.stringify(dataObject));
  output.setMimeType(ContentService.MimeType.JSON);
  return output;
}

/**
 * ==============================================================================
 * FUNGSI TESTING: Uji Langsung dari Editor Apps Script
 * ==============================================================================
 */
function testUploadFoto() {
  Logger.log('🚀 Memulai pengujian upload foto ke Google Drive & Spreadsheet...');

  const sampleBase64 = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

  const mockPayload = {
    base64: sampleBase64,
    unit: 'TEST-E2168',
    category: 'TEST_ACH',
    slot: 1,
    jobId: 'TEST-JOB-' + Math.floor(1000 + Math.random() * 9000),
    filename: 'TEST_PHOTO_' + Utilities.formatDate(new Date(), 'Asia/Makassar', 'yyyyMMdd_HHmmss') + '.png'
  };

  const result = processUploadAndSave(mockPayload);
  Logger.log('================================================================');
  Logger.log('Hasil Test: ' + JSON.stringify(result));
  Logger.log('================================================================');
  return createJsonResponse(result);
}

function testKoneksiDriveDanSpreadsheet() {
  Logger.log('🔍 Menguji koneksi Spreadsheet ID: ' + SPREADSHEET_ID);
  try {
    const ss = getTargetSpreadsheet();
    if (ss) {
      Logger.log('✅ Spreadsheet Terkoneksi: ' + ss.getName());
      Logger.log('📊 URL Spreadsheet: ' + ss.getUrl());
    } else {
      Logger.log('❌ Gagal membuka spreadsheet');
    }

    const folder = getTargetFolder(ss);
    Logger.log('✅ Folder Drive Terkoneksi: ' + folder.getName());
    Logger.log('🔗 URL Folder: ' + folder.getUrl());

    Logger.log('🎉 SEMUA KONEKSI SIAP DIGUNAKAN!');
  } catch (err) {
    Logger.log('❌ Gagal mengakses Google Drive / Spreadsheet: ' + err.toString());
  }
}
