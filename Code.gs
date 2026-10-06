/**
 * ==============================================================================
 * GOOGLE APPS SCRIPT: UPLOAD FOTO OPERASIONAL KE GOOGLE DRIVE & SPREADSHEET
 * SE MANAGEMENT JOB - MINE OPERATIONS
 * ==============================================================================
 * Target Folder ID   : 11EQ_NsZYeMmEKURpibXCRtyrQw5kKkh3
 * Target Folder URL  : https://drive.google.com/drive/folders/11EQ_NsZYeMmEKURpibXCRtyrQw5kKkh3?usp=drive_link
 * Target Spreadsheet : Otomatis dibuat & dicatat di dalam folder yang sama
 *
 * CARA MENGUJI (TEST) DI GOOGLE APPS SCRIPT:
 * ------------------------------------------------------------------------------
 * 1. Di bagian atas editor Apps Script, pada dropdown fungsi (di sebelah tombol "Debug"),
 *    pilih fungsi "testUploadFoto" atau "testKoneksiDriveDanSpreadsheet".
 * 2. Klik tombol "Jalankan" (Run).
 * 3. Buka tab "Log eksekusi" di bawah untuk melihat hasil sukses, tautan Drive, dan Spreadsheet!
 *
 * PANDUAN DEPLOY SEBAGAI WEB APP:
 * ------------------------------------------------------------------------------
 * 1. Klik tombol biru "Deploy" (Terapkan) di kanan atas -> pilih "New deployment".
 * 2. Klik ikon roda gigi ⚙️ di samping "Select type" -> pilih "Web app".
 * 3. Atur konfigurasi:
 *    - Description   : SE Management Job Photo Upload API
 *    - Execute as    : Me (akun Google Anda)
 *    - Who has access: Anyone (Siapa saja)  <-- WAJIB PILIH INI agar web app bisa upload tanpa login
 * 4. Klik tombol "Deploy", lalu klik "Authorize access" dan izinkan akses.
 * 5. Salin "Web app URL" (berakhiran /exec).
 * 6. Tempelkan URL tersebut ke APPS_SCRIPT_CONFIG.uploadEndpointUrl di index.html.
 * ==============================================================================
 */

// ID Folder Google Drive Tujuan
const TARGET_FOLDER_ID = '11EQ_NsZYeMmEKURpibXCRtyrQw5kKkh3';

// Nama File Google Spreadsheet untuk Log Riwayat Foto
const SPREADSHEET_LOG_NAME = 'LOG_FOTO_SE_MANAGEMENT_JOB';

/**
 * ==============================================================================
 * FUNGSI TESTING 1: Menguji Upload Foto ke Google Drive & Catat ke Spreadsheet
 * (Pilih fungsi ini di dropdown atas lalu klik tombol "Jalankan")
 * ==============================================================================
 */
function testUploadFoto() {
  Logger.log('🚀 Memulai pengujian upload foto ke Google Drive & Spreadsheet...');

  // Gambar contoh PNG 1x1 pixel transparan berformat Base64 untuk pengetesan aman
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
  if (result.status === 'success') {
    Logger.log('✅ TEST BERHASIL 100%!');
    Logger.log('📁 File ID Drive   : ' + result.fileId);
    Logger.log('🖼️ Nama File       : ' + result.fileName);
    Logger.log('🔗 Link Direct Foto: ' + result.directUrl);
    Logger.log('📂 Link Buka Drive : ' + result.driveViewUrl);
    Logger.log('📊 Spreadsheet Log : ' + (result.spreadsheetUrl || 'Tercatat di ' + SPREADSHEET_LOG_NAME));
    Logger.log('Silakan buka folder Google Drive Anda dan Spreadsheet untuk melihat foto & log yang baru masuk!');
  } else {
    Logger.log('❌ TEST GAGAL: ' + result.message);
  }
  Logger.log('================================================================');

  return createJsonResponse(result);
}

/**
 * ==============================================================================
 * FUNGSI TESTING 2: Menguji Akses Folder Drive & Spreadsheet Log
 * ==============================================================================
 */
function testKoneksiDriveDanSpreadsheet() {
  Logger.log('🔍 Menguji koneksi ke Google Drive folder ID: ' + TARGET_FOLDER_ID);
  try {
    const folder = DriveApp.getFolderById(TARGET_FOLDER_ID);
    Logger.log('✅ Folder Drive Terkoneksi: ' + folder.getName());
    Logger.log('🔗 URL Folder: ' + folder.getUrl());

    const sheet = getOrCreateLogSpreadsheet(folder);
    Logger.log('✅ Spreadsheet Log Terkoneksi: ' + sheet.getName());
    Logger.log('📊 URL Spreadsheet: ' + sheet.getUrl());
    Logger.log('🎉 SEMUA KONEKSI SIAP DIGUNAKAN!');
  } catch (err) {
    Logger.log('❌ Gagal mengakses Google Drive: ' + err.toString());
  }
}

/**
 * ==============================================================================
 * ENDPOINT UTAMA: Menerima POST request dari aplikasi Web (index.html)
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
 * ENDPOINT GET: Health Check
 * ==============================================================================
 */
function doGet(e) {
  try {
    const targetFolder = DriveApp.getFolderById(TARGET_FOLDER_ID);
    return createJsonResponse({
      status: 'ok',
      service: 'SE Management Job - Google Drive & Spreadsheet Photo Upload API',
      folderId: TARGET_FOLDER_ID,
      folderName: targetFolder.getName(),
      folderUrl: targetFolder.getUrl(),
      timestamp: new Date().toISOString()
    });
  } catch (err) {
    return createJsonResponse({
      status: 'error',
      message: 'Folder Google Drive tidak dapat diakses: ' + err.toString(),
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

  // Simpan berkas ke Google Drive Folder
  const targetFolder = DriveApp.getFolderById(TARGET_FOLDER_ID);
  if (!targetFolder) {
    throw new Error('Folder Google Drive ID ' + TARGET_FOLDER_ID + ' tidak ditemukan!');
  }

  const createdFile = targetFolder.createFile(blob);

  // Set izin akses siap pakai untuk tampilan web
  try {
    createdFile.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
  } catch (permErr) {
    Logger.log('Peringatan saat set sharing permission: ' + permErr.toString());
  }

  const fileId = createdFile.getId();
  const directImageUrl = 'https://lh3.googleusercontent.com/d/' + fileId;
  const driveViewUrl = createdFile.getUrl();
  const driveDownloadUrl = 'https://drive.google.com/uc?export=view&id=' + fileId;

  // Catat riwayat unggahan ke Google Spreadsheet
  let spreadsheetUrl = '';
  try {
    const ss = getOrCreateLogSpreadsheet(targetFolder);
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
  } catch (sheetErr) {
    Logger.log('Peringatan saat mencatat ke Spreadsheet: ' + sheetErr.toString());
  }

  return {
    status: 'success',
    message: 'Foto berhasil disimpan ke Google Drive dan dicatat di Spreadsheet!',
    fileId: fileId,
    fileName: fileName,
    url: directImageUrl,          // URL utama untuk <img src="...">
    directUrl: directImageUrl,
    driveViewUrl: driveViewUrl,
    driveDownloadUrl: driveDownloadUrl,
    spreadsheetUrl: spreadsheetUrl,
    folderId: TARGET_FOLDER_ID,
    uploadedAt: new Date().toISOString()
  };
}

/**
 * ==============================================================================
 * HELPER SPREADSHEET: Ambil atau Buat Spreadsheet Log di dalam Folder Drive
 * ==============================================================================
 */
function getOrCreateLogSpreadsheet(folder) {
  const files = folder.getFilesByName(SPREADSHEET_LOG_NAME);
  let ss = null;

  if (files.hasNext()) {
    const file = files.next();
    ss = SpreadsheetApp.openById(file.getId());
  } else {
    // Buat Google Spreadsheet baru di folder target
    ss = SpreadsheetApp.create(SPREADSHEET_LOG_NAME);
    const ssFile = DriveApp.getFileById(ss.getId());
    folder.addFile(ssFile);
    DriveApp.getRootFolder().removeFile(ssFile); // Hapus dari root agar tersimpan rapi hanya di folder target

    // Format Header Sheet
    const sheet = ss.getActiveSheet();
    sheet.setName('Log Foto Operasional');
    sheet.appendRow([
      'No',
      'Waktu Upload (WITA)',
      'No Unit / Lambung',
      'Kategori Pekerjaan',
      'Slot Foto',
      'Job ID',
      'Nama File',
      'ID File Google Drive',
      'Preview Thumbnail',
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
  }

  return ss;
}

/**
 * ==============================================================================
 * HELPER ROW: Tambahkan Baris Data Baru ke Spreadsheet
 * ==============================================================================
 */
function appendLogRow(spreadsheet, info) {
  const sheet = spreadsheet.getSheetByName('Log Foto Operasional') || spreadsheet.getActiveSheet();
  const lastRow = sheet.getLastRow();
  const noUrut = lastRow; // karena baris 1 adalah header
  const waktuStr = Utilities.formatDate(new Date(), 'Asia/Makassar', 'dd/MM/yyyy HH:mm:ss');

  // Gunakan formula IMAGE agar thumbnail foto langsung muncul di sel spreadsheet
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

  // Sesuaikan tinggi baris agar gambar thumbnail terlihat jelas
  try {
    sheet.setRowHeight(sheet.getLastRow(), 45);
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
