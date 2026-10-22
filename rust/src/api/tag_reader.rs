use std::{
    collections::{HashSet, HashMap},
    fs::{self},
    io::{self, Cursor, Write},
    path::{Path, PathBuf},
    time::{Duration, UNIX_EPOCH},
};

use image::imageops;
use lofty::prelude::{Accessor, AudioFile, ItemKey, TaggedFileExt};
use windows::{
    core::Interface,
    core::HSTRING,
    Storage::{
        FileProperties::{ThumbnailMode, ThumbnailType},
        StorageFile,
        Streams::{DataReader, IInputStream},
    },
};

use crate::frb_generated::StreamSink;

use super::logger::log_to_dart;

/// K: extension, V: can read tags by using Lofty
static SUPPORT_FORMAT: phf::Map<&'static str, bool> = phf::phf_map! {
    "mp3" => true, "mp2" => false, "mp1" => false,
    "ogg" => true,
    "wav" => true, "wave" => true,
    "aif" => true, "aiff" => true, "aifc" => true,
    // 通过 Windows 系统支持
    "asf" => false, "wma" => false,
    "aac" => true, "adts" => true,
    "m4a" => true,
    "ac3" => false,
    "amr" => false, "3ga" => false,
    "flac" => true,
    "mpc" => true,
    // 插件支持
    "mid" => false,
    "wv" => true, "wvc" => true,
    "opus" => true,
    "dsf" => false, "dff" => false,
    "ape" => true,
};

pub struct IndexActionState {
    /// completed / total
    pub progress: f64,

    /// describe action state
    pub message: String,
}

#[derive(Debug)]
struct Audio {
    title: String,
    artist: String,
    album: String,
    track: Option<u32>,
    /// in secs
    duration: u64,
    /// kbps
    bitrate: Option<u32>,
    sample_rate: Option<u32>,
    /// absolute path
    path: String,
    /// secs since UNIX_EPOCH
    modified: u64,
    /// secs since UNIX_EPOCH
    created: u64,
    /// 标签获取方式
    by: Option<String>,
}

impl Audio {
    fn new_with_path(path: impl AsRef<Path>, by: Option<String>) -> Option<Self> {
        let path = path.as_ref();
        Some(Audio {
            title: path.file_name()?.to_string_lossy().to_string(),
            artist: "UNKNOWN".to_string(),
            album: "UNKNOWN".to_string(),
            track: None,
            duration: 0,
            bitrate: None,
            sample_rate: None,
            path: path.to_string_lossy().to_string(),
            modified: 0,
            created: 0,
            by,
        })
    }

    fn to_json_value(&self) -> serde_json::Value {
        serde_json::json!({
            "title": self.title,
            "artist": self.artist,
            "album": self.album,
            "track": self.track,
            "duration": self.duration,
            "bitrate": self.bitrate,
            "sample_rate": self.sample_rate,
            "path": self.path,
            "modified": self.modified,
            "created": self.created,
            "by": self.by
        })
    }

    /// 不支持：None  
    /// Lofty 能获取到信息：read_by_lofty  
    /// 不能的话：read_by_win_music_properties  
    /// 再不能的话：title: filename 代替
    fn read_from_path(path: impl AsRef<Path>) -> Option<Self> {
        let path = path.as_ref();
        let lofty_support: bool =
            *SUPPORT_FORMAT.get(&path.extension()?.to_ascii_lowercase().to_string_lossy())?;

        let file_metadata = match fs::metadata(path) {
            Ok(val) => val,
            Err(err) => {
                log_to_dart(err.to_string());
                return None;
            }
        };
        let modified = file_metadata
            .modified()
            .unwrap_or(UNIX_EPOCH)
            .duration_since(UNIX_EPOCH)
            .unwrap_or(Duration::ZERO)
            .as_secs();
        let created = file_metadata
            .created()
            .unwrap_or(UNIX_EPOCH)
            .duration_since(UNIX_EPOCH)
            .unwrap_or(Duration::ZERO)
            .as_secs();

        if lofty_support {
            if let Some(value) = Self::read_by_lofty(path, modified, created) {
                return Some(value);
            }

            match Self::read_by_win_music_properties(path, modified, created) {
                Ok(value) => Some(value),
                Err(err) => {
                    log_to_dart(format!("{:?}: {}", path, err));
                    return Self::new_with_path(path, None);
                }
            }
        } else {
            match Self::read_by_win_music_properties(path, modified, created) {
                Ok(value) => Some(value),
                Err(err) => {
                    log_to_dart(format!("{:?}: {}", path, err));
                    return Self::new_with_path(path, None);
                }
            }
        }
    }

    /// 使用 lofty 获取音乐标签。只在文件名不正确、没有标签或包含不支持的编码时返回 None
    fn read_by_lofty(path: impl AsRef<Path>, modified: u64, created: u64) -> Option<Self> {
        let path = path.as_ref();
        let tagged_file = match lofty::read_from_path(path) {
            Ok(val) => val,
            Err(err) => {
                log_to_dart(format!("{:?}: {}", path, err));
                return None;
            }
        };

        let properties = tagged_file.properties();

        if let Some(tag) = tagged_file
            .primary_tag()
            .or_else(|| tagged_file.first_tag())
        {
            let artist_strs: Vec<_> = tag.get_strings(&ItemKey::TrackArtist).collect();
            let artist = if artist_strs.is_empty() {
                std::borrow::Cow::Borrowed("UNKNOWN").to_string()
            } else {
                artist_strs.join("/")
            };

            return Some(Audio {
                title: tag
                    .title()
                    .unwrap_or(path.file_name()?.to_string_lossy())
                    .to_string(),
                artist,
                album: tag
                    .album()
                    .unwrap_or(std::borrow::Cow::Borrowed("UNKNOWN"))
                    .to_string(),
                track: tag.track(),
                duration: properties.duration().as_secs(),
                bitrate: properties.audio_bitrate(),
                sample_rate: properties.sample_rate(),
                path: path.to_string_lossy().to_string(),
                modified,
                created,
                by: Some("Lofty".to_string()),
            });
        }

        return Some(Audio {
            title: path.file_name()?.to_string_lossy().to_string(),
            artist: std::borrow::Cow::Borrowed("UNKNOWN").to_string(),
            album: std::borrow::Cow::Borrowed("UNKNOWN").to_string(),
            track: None,
            duration: properties.duration().as_secs(),
            bitrate: properties.audio_bitrate(),
            sample_rate: properties.sample_rate(),
            path: path.to_string_lossy().to_string(),
            modified,
            created,
            by: Some("Lofty".to_string()),
        });
    }

    /// 使用 Windows Api 获取音乐标签。会因为各种原因返回 Err
    fn read_by_win_music_properties(
        path: impl AsRef<Path>,
        modified: u64,
        created: u64,
    ) -> Result<Self, windows::core::Error> {
        let path = path.as_ref();
        let storage_file = StorageFile::GetFileFromPathAsync(&HSTRING::from(path))?.get()?;
        let music_properties = storage_file
            .Properties()?
            .GetMusicPropertiesAsync()?
            .get()?;

        let duration: Duration = music_properties.Duration()?.into();

        let mut title = music_properties
            .Title()
            .or_else(|_| storage_file.Name())?
            .to_string();
        if title.is_empty() {
            title = storage_file.Name()?.to_string();
        }

        let mut artist = music_properties
            .Artist()
            .unwrap_or(HSTRING::from("UNKNOWN"))
            .to_string();
        if artist.is_empty() {
            artist = "UNKNOWN".to_string();
        }

        let mut album = music_properties
            .Album()
            .unwrap_or(HSTRING::from("UNKNOWN"))
            .to_string();
        if album.is_empty() {
            album = "UNKNOWN".to_string();
        }

        Ok(Audio {
            title,
            artist,
            album,
            track: Some(music_properties.TrackNumber()?),
            duration: duration.as_secs(),
            bitrate: Some(music_properties.Bitrate()? / 1000),
            sample_rate: None,
            path: path.to_string_lossy().to_string(),
            modified,
            created,
            by: Some("Windows".to_string()),
        })
    }
}

#[derive(Debug)]
struct AudioFolder {
    path: String,
    /// secs since UNIX_EPOCH
    modified: u64,
    /// biggest created in audios. secs since UNIX_EPOCH
    latest: u64,
    audios: Vec<Audio>,
}

impl AudioFolder {
    fn to_json_value(&self) -> serde_json::Value {
        let mut audios_json: Vec<serde_json::Value> = vec![];
        for audio in &self.audios {
            audios_json.push(audio.to_json_value());
        }

        serde_json::json!({
            "path": self.path,
            "modified": self.modified,
            "latest": self.latest,
            "audios": audios_json,
        })
    }

    /// 扫描路径为 path 的文件夹
    fn read_from_folder(path: impl AsRef<Path>) -> Result<AudioFolder, io::Error> {
        let path = path.as_ref();

        let dir = match fs::read_dir(path) {
            Ok(val) => val,
            Err(err) => {
                log_to_dart(format!("{:?}: {}", path, err));
                return Err(err);
            }
        };

        let mut audios: Vec<Audio> = vec![];
        let mut latest: u64 = 0;

        for item in dir {
            let entry = match item {
                Ok(value) => value,
                Err(_) => continue,
            };

            let file_type = match entry.file_type() {
                Ok(value) => value,
                Err(_) => continue,
            };

            if file_type.is_file() {
                if let Some(audio_item) = Audio::read_from_path(entry.path()) {
                    if audio_item.created > latest {
                        latest = audio_item.created;
                    }

                    audios.push(audio_item);
                }
            }
        }

        if !audios.is_empty() {
            return Ok(AudioFolder {
                path: path.to_string_lossy().to_string(),
                modified: fs::metadata(path)?
                    .modified()?
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or(Duration::ZERO)
                    .as_secs(),
                latest,
                audios,
            });
        }

        Err(io::Error::new(
            io::ErrorKind::NotFound,
            path.to_string_lossy() + " has no music.",
        ))
    }

    /// 扫描路径为 path 的文件夹及其所有子文件夹。
    fn read_from_folder_recursively(
        folder: impl AsRef<Path>,
        result: &mut Vec<Self>,
        scaned_count: &mut u64,
        total_count: &mut u64,
        scaned_folders: &mut HashSet<String>,
        sink: &StreamSink<IndexActionState>,
    ) -> Result<(), io::Error> {
        let folder = folder.as_ref();
        if scaned_folders.contains(&folder.to_string_lossy().to_string()) {
            return Ok(());
        }

        let dir = match fs::read_dir(folder) {
            Ok(val) => val,
            Err(err) => {
                log_to_dart(format!("{:?}: {}", folder, err));
                return Ok(());
            }
        };

        let _ = sink.add(IndexActionState {
            progress: *scaned_count as f64 / *total_count as f64,
            message: String::from("正在扫描 ") + &folder.to_string_lossy(),
        });

        scaned_folders.insert(folder.to_string_lossy().to_string());
        let mut audios: Vec<Audio> = vec![];
        let mut latest: u64 = 0;

        for item in dir {
            let entry = match item {
                Ok(value) => value,
                Err(err) => {
                    log_to_dart(err.to_string());
                    continue;
                }
            };

            let file_type = match entry.file_type() {
                Ok(value) => value,
                Err(err) => {
                    log_to_dart(err.to_string());
                    continue;
                }
            };

            if file_type.is_dir() {
                *total_count += 1;
                let _ = Self::read_from_folder_recursively(
                    entry.path(),
                    result,
                    scaned_count,
                    total_count,
                    scaned_folders,
                    sink,
                );
            } else if let Some(metadata) = Audio::read_from_path(entry.path()) {
                if metadata.created > latest {
                    latest = metadata.created;
                }

                audios.push(metadata);
            }
        }

        if !audios.is_empty() {
            if let Ok(metadata) = fs::metadata(folder) {
                if let Ok(modified) = metadata.modified() {
                    result.push(AudioFolder {
                        path: folder.to_string_lossy().to_string(),
                        modified: modified
                            .duration_since(UNIX_EPOCH)
                            .unwrap_or(Duration::ZERO)
                            .as_secs(),
                        latest,
                        audios,
                    });
                }
            }
        }

        *scaned_count += 1;
        let _ = sink.add(IndexActionState {
            progress: *scaned_count as f64 / *total_count as f64,
            message: String::new(),
        });

        Ok(())
    }
}

fn _get_picture_by_windows(path: &String) -> Result<Vec<u8>, windows::core::Error> {
    let file = StorageFile::GetFileFromPathAsync(&HSTRING::from(path))?.get()?;
    let thumbnail = file
        .GetThumbnailAsyncOverloadDefaultSizeDefaultOptions(ThumbnailMode::MusicView)?
        .get()?;

    // Shell file-type icons are not album art. Let Flutter render its themed
    // placeholder when the file has no actual thumbnail.
    if thumbnail.Type()? != ThumbnailType::Image {
        thumbnail.Close()?;
        return Ok(Vec::new());
    }
    let size = thumbnail.Size()? as u32;
    let stream: IInputStream = thumbnail.cast()?;

    let mut buffer = vec![0u8; size as usize];
    let data_reader = DataReader::CreateDataReader(&stream)?;
    data_reader.LoadAsync(size)?.get()?;
    data_reader.ReadBytes(&mut buffer)?;

    data_reader.Close()?;
    stream.Close()?;

    Ok(buffer)
}

fn _get_picture_by_lofty(path: &String) -> Option<Vec<u8>> {
    if let Ok(tagged_file) = lofty::read_from_path(&path) {
        let tag = tagged_file
            .primary_tag()
            .or_else(|| tagged_file.first_tag())?;

        return Some(tag.pictures().first()?.data().to_vec());
    }

    None
}

/// for Flutter  
/// 如果无法通过 Lofty 获取则通过 Windows 获取
pub fn get_picture_from_path(path: String, width: u32, height: u32) -> Option<Vec<u8>> {
    let pic_option =
        _get_picture_by_lofty(&path).or_else(|| match _get_picture_by_windows(&path) {
            Ok(val) if val.is_empty() => None,
            Ok(val) => Some(val),
            Err(err) => {
                log_to_dart(format!("fail to get pic: {}", err));
                None
            }
        });

    if let Some(pic) = &pic_option {
        if let Ok(loaded_pic) = image::load_from_memory(pic) {
            // 计算新的宽高，保持原比例
            let pic_ratio = loaded_pic.width() as f32 / loaded_pic.height() as f32;

            let (result_width, result_height) = if pic_ratio > 1.0 {
                (width, (width as f32 / pic_ratio).round() as u32)
            } else {
                ((height as f32 * pic_ratio).round() as u32, height)
            };

            let resized_img = imageops::resize(
                &loaded_pic,
                result_width,
                result_height,
                imageops::FilterType::Triangle,
            );

            let mut output = Cursor::new(Vec::new());
            if let Ok(_) = resized_img.write_to(&mut output, image::ImageFormat::Png) {
                return Some(output.into_inner());
            }
        }
    }

    pic_option
}

fn _get_lyric_from_lofty(path: &String) -> Option<String> {
    if let Ok(tagged_file) = lofty::read_from_path(&path) {
        let tag = tagged_file
            .primary_tag()
            .or_else(|| tagged_file.first_tag())?;
        let lyric_tag = tag.get(&ItemKey::Lyrics)?;
        let lyric = lyric_tag.value().text()?;

        return Some(lyric.to_string());
    }

    None
}

fn _get_lyric_from_lrc_file(path: &String) -> anyhow::Result<String> {
    let mut lrc_file_path = PathBuf::from(path);
    lrc_file_path.set_extension("lrc");

    let lrc_bytes = fs::read(lrc_file_path)?;

    let is_le = lrc_bytes.starts_with(&[0xFF, 0xFE]);
    let is_utf16 = (is_le || lrc_bytes.starts_with(&[0xFE, 0xFF])) && lrc_bytes.len() % 2 == 0;

    if is_utf16 {
        let convert_fn = match is_le {
            true => u16::from_le_bytes,
            false => u16::from_be_bytes,
        };

        let mut u16_bytes: Vec<u16> = vec![];
        let mut chunk_iter = lrc_bytes.chunks_exact(2);
        chunk_iter.next();

        for chunk in chunk_iter {
            u16_bytes.push(convert_fn([chunk[0], chunk[1]]));
        }
        return Ok(String::from_utf16(&u16_bytes)?);
    }

    return Ok(String::from_utf8(lrc_bytes)?);
}

/// for Flutter   
/// 只支持读取 ID3V2, VorbisComment, Mp4Ilst 存储的内嵌歌词
/// 以及相同目录相同文件名的 .lrc 外挂歌词（utf-8 or utf-16）
pub fn get_lyric_from_path(path: String) -> Option<String> {
    return _get_lyric_from_lofty(&path).or_else(|| match _get_lyric_from_lrc_file(&path) {
        Ok(val) => Some(val),
        Err(err) => {
            log_to_dart(format!("fail to get lrc: {}", err.to_string()));
            None
        }
    });
}

/// for Flutter  
/// 扫描给定路径下所有子文件夹（包括自己）的音乐文件并把索引保存在 index_path/index.json。
pub fn build_index_from_folders_recursively(
    folders: Vec<String>,
    index_path: String,
    sink: StreamSink<IndexActionState>,
) -> Result<(), io::Error> {
    let mut audio_folders: Vec<AudioFolder> = vec![];
    let mut scaned: u64 = 0;
    let mut total: u64 = folders.len() as u64;
    let mut scaned_folders: HashSet<String> = HashSet::new();

    for item in &folders {
        let _ = AudioFolder::read_from_folder_recursively(
            Path::new(item),
            &mut audio_folders,
            &mut scaned,
            &mut total,
            &mut scaned_folders,
            &sink,
        );
    }

    let mut audio_folders_json: Vec<serde_json::Value> = vec![];
    for item in &audio_folders {
        audio_folders_json.push(item.to_json_value());
    }
    let json_value = serde_json::json!({
        "version": 110,
        "folders": audio_folders_json,
        "roots": folders,
    });

    let mut index_path = PathBuf::from(index_path);
    index_path.push("index.json");
    _write_index(&index_path, &json_value)?;

    Ok(())
}

fn _update_index_below_1_1_0(
    index: &serde_json::Value,
    index_path: &PathBuf,
    sink: &StreamSink<IndexActionState>,
) -> Result<(), io::Error> {
    let mut audio_folders_json: Vec<serde_json::Value> = vec![];
    let folders = index.as_array().unwrap();
    for item in folders {
        let path = item["path"].as_str().unwrap();
        let _ = sink.add(IndexActionState {
            progress: audio_folders_json.len() as f64 / folders.len() as f64,
            message: String::from("正在扫描 ") + path,
        });
        let folder_path = Path::new(path);
        if let Ok(audio_folder) = AudioFolder::read_from_folder(folder_path) {
            audio_folders_json.push(audio_folder.to_json_value());
            let _ = sink.add(IndexActionState {
                progress: audio_folders_json.len() as f64 / folders.len() as f64,
                message: String::new(),
            });
        }
    }
    fs::File::create(index_path)?.write_all(
        serde_json::json!({
            "version": 110,
            "folders": audio_folders_json,
        })
        .to_string()
        .as_bytes(),
    )?;

    Ok(())
}

/// for Flutter   
/// 读取 index_path/index.json，检查更新。不可能重新读取被修改的文件夹下所有的音乐标签，这样太耗时。  
///
/// [LOWEST_VERSION] 指定可以继承的 index 的最低版本。
/// 如果 index version < [LOWEST_VERSION] 或者是 index 根本没有 version 再或者格式不符合要求，就转到
/// [_update_index_below_1_1_0] 更新 index；
/// 如果 index version >= [LOWEST_VERSION] 则进行更新。
///
/// 如果文件夹不存在，删除记录。  
/// 如果文件夹被修改（再次读取到的 modified > 记录的 modified），就更新它。没有则跳过它
/// 1. 遍历该文件夹索引，判断文件是否存在，不存在则删除记录
/// 2. 遍历该文件夹索引，如果文件被修改（再次读取到的 modified > 记录的 modified），重新读取标签；没有则跳过它
/// 3. 遍历该文件夹，添加新增（读取到的 created > 记录的 latest）的音乐文件
pub fn update_index(index_path: String, sink: StreamSink<IndexActionState>) -> anyhow::Result<()> {
    let index_path = PathBuf::from(index_path).join("index.json");
    let mut index: serde_json::Value = match fs::read(&index_path)
        .map_err(anyhow::Error::from)
        .and_then(|bytes| Ok(serde_json::from_slice(&bytes)?)) {
        Ok(value) => value,
        Err(original) => {
            let backup = index_path.with_extension("json.bak");
            if !backup.exists() { return Err(original); }
            serde_json::from_slice(&fs::read(backup)?)?
        }
    };
    if index.is_array() {
        return Ok(_update_index_below_1_1_0(&index, &index_path, &sink)?);
    }
    _refresh_index(&mut index, |folder| {
        let _ = sink.add(IndexActionState {
            progress: 0.0,
            message: format!("正在检查 {}", folder),
        });
    })?;
    _write_index(&index_path, &index)?;
    let _ = sink.add(IndexActionState { progress: 1.0, message: String::new() });
    Ok(())
}

fn _write_index(path: &Path, value: &serde_json::Value) -> io::Result<()> {
    let temporary = path.with_extension("json.tmp");
    let mut file = fs::File::create(&temporary)?;
    file.write_all(value.to_string().as_bytes())?;
    file.sync_all()?;
    drop(file);
    if let Ok(old) = fs::read(path) {
        if serde_json::from_slice::<serde_json::Value>(&old).is_ok() {
            let backup_tmp = path.with_extension("json.bak.tmp");
            let mut backup = fs::File::create(&backup_tmp)?;
            backup.write_all(&old)?;
            backup.sync_all()?;
            drop(backup);
            fs::rename(backup_tmp, path.with_extension("json.bak"))?;
        }
    }
    fs::rename(temporary, path)
}

fn _path_key(path: &Path) -> String {
    path.to_string_lossy().replace('/', "\\").to_lowercase()
}

fn _refresh_index(index: &mut serde_json::Value, mut progress: impl FnMut(&str)) -> anyhow::Result<()> {
    let folders = index["folders"].as_array()
        .ok_or_else(|| anyhow::anyhow!("Invalid music index: folders must be an array"))?;
    let mut indexed = HashMap::new();
    for folder in folders {
        let path = folder["path"].as_str()
            .ok_or_else(|| anyhow::anyhow!("Invalid music folder path"))?;
        indexed.insert(_path_key(Path::new(path)), folder.clone());
    }
    let roots: Vec<String> = match index["roots"].as_array() {
        Some(roots) => roots.iter().filter_map(|r| r.as_str().map(String::from)).collect(),
        None => folders.iter().filter_map(|f| f["path"].as_str().map(String::from)).collect(),
    };
    let mut visited = HashSet::new();
    for root in &roots {
        _refresh_folder(Path::new(root), &mut indexed, &mut visited, &mut progress);
    }
    // Unreachable folders stay indexed so unplugged disks do not lose their library.
    let mut folders: Vec<_> = indexed.into_values().collect();
    folders.sort_by(|a, b| a["path"].as_str().cmp(&b["path"].as_str()));
    index["folders"] = serde_json::json!(folders);
    index["roots"] = serde_json::json!(roots);
    Ok(())
}

fn _refresh_folder(
    path: &Path,
    indexed: &mut HashMap<String, serde_json::Value>,
    visited: &mut HashSet<String>,
    progress: &mut impl FnMut(&str),
) {
    let canonical = match fs::canonicalize(path) { Ok(p) => p, Err(_) => return };
    if !visited.insert(_path_key(&canonical)) { return; }
    let entries: Vec<_> = match fs::read_dir(path).and_then(|entries| entries.collect::<io::Result<Vec<_>>>()) {
        Ok(entries) => entries,
        Err(_) => return,
    };
    progress(&path.to_string_lossy());
    let key = _path_key(path);
    let mut old_audios = HashMap::new();
    if let Some(audios) = indexed.get(&key).and_then(|f| f["audios"].as_array()) {
        for audio in audios {
            if let Some(path) = audio["path"].as_str() {
                old_audios.insert(_path_key(Path::new(path)), audio.clone());
            }
        }
    }
    let mut audios = Vec::new();
    for entry in entries {
        let file_type = match entry.file_type() { Ok(t) => t, Err(_) => return };
        if file_type.is_symlink() { continue; }
        if file_type.is_dir() {
            _refresh_folder(&entry.path(), indexed, visited, progress);
            continue;
        }
        if !file_type.is_file() { continue; }
        let file_key = _path_key(&entry.path());
        let metadata = match entry.metadata() { Ok(m) => m, Err(_) => return };
        let modified_ns = metadata.modified().unwrap_or(UNIX_EPOCH)
            .duration_since(UNIX_EPOCH).unwrap_or_default().as_nanos() as u64;
        let old = old_audios.get(&file_key);
        if let Some(old) = old {
            if old["size"].as_u64() == Some(metadata.len())
                && old["modified_ns"].as_u64() == Some(modified_ns) {
                audios.push(old.clone());
                continue;
            }
        }
        if let Some(audio) = Audio::read_from_path(entry.path()) {
            let mut value = audio.to_json_value();
            value["size"] = serde_json::json!(metadata.len());
            value["modified_ns"] = serde_json::json!(modified_ns);
            audios.push(value);
        } else if let Some(old) = old {
            audios.push(old.clone());
        }
    }
    audios.sort_by(|a, b| a["path"].as_str().cmp(&b["path"].as_str()));
    let latest = audios.iter().filter_map(|a| a["created"].as_u64()).max().unwrap_or(0);
    let modified = fs::metadata(path).and_then(|m| m.modified()).unwrap_or(UNIX_EPOCH)
        .duration_since(UNIX_EPOCH).unwrap_or_default().as_secs();
    if !audios.is_empty() || indexed.contains_key(&key) {
        indexed.insert(key, serde_json::json!({
            "path": path.to_string_lossy(), "modified": modified,
            "latest": latest, "audios": audios,
        }));
    }
}
#[cfg(test)]
mod reliability_tests {
    use super::*;
    struct Fixture(PathBuf);
    impl Fixture {
        fn new() -> Self {
            let name = format!("coriander-index-{}-{}", std::process::id(),
                std::time::SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos());
            let path = std::env::temp_dir().join(name);
            fs::create_dir_all(&path).unwrap();
            Self(path)
        }
        fn index(&self) -> serde_json::Value {
            serde_json::json!({"version":110,"roots":[self.0.to_string_lossy()],"folders":[]})
        }
    }
    impl Drop for Fixture { fn drop(&mut self) { let _ = fs::remove_dir_all(&self.0); } }
    fn wav(path: &Path, samples: u32) {
        let size = samples * 2;
        let mut bytes = Vec::new();
        bytes.extend_from_slice(b"RIFF"); bytes.extend_from_slice(&(36 + size).to_le_bytes());
        bytes.extend_from_slice(b"WAVEfmt "); bytes.extend_from_slice(&16u32.to_le_bytes());
        bytes.extend_from_slice(&1u16.to_le_bytes()); bytes.extend_from_slice(&1u16.to_le_bytes());
        bytes.extend_from_slice(&8000u32.to_le_bytes()); bytes.extend_from_slice(&16000u32.to_le_bytes());
        bytes.extend_from_slice(&2u16.to_le_bytes()); bytes.extend_from_slice(&16u16.to_le_bytes());
        bytes.extend_from_slice(b"data"); bytes.extend_from_slice(&size.to_le_bytes());
        bytes.resize((44 + size) as usize, 0);
        fs::write(path, bytes).unwrap();
    }
    #[test]
    fn discovers_old_timestamp_files_and_new_subdirectories() {
        let fixture = Fixture::new();
        let mut index = fixture.index();
        _refresh_index(&mut index, |_| {}).unwrap();
        let nested = fixture.0.join("new-album");
        fs::create_dir_all(&nested).unwrap();
        wav(&nested.join("song.wav"), 800);
        _refresh_index(&mut index, |_| {}).unwrap();
        assert_eq!(index["folders"].as_array().unwrap().len(), 1);
        index["folders"][0]["latest"] = serde_json::json!(u64::MAX);
        wav(&nested.join("another.wav"), 800);
        _refresh_index(&mut index, |_| {}).unwrap();
        assert_eq!(index["folders"][0]["audios"].as_array().unwrap().len(), 2);
    }
    #[test]
    fn reuses_unchanged_tags_but_detects_file_changes_and_deletions() {
        let fixture = Fixture::new();
        let file = fixture.0.join("song.wav");
        wav(&file, 800);
        let mut index = fixture.index();
        _refresh_index(&mut index, |_| {}).unwrap();
        index["folders"][0]["audios"][0]["title"] = serde_json::json!("cached-title");
        _refresh_index(&mut index, |_| {}).unwrap();
        assert_eq!(index["folders"][0]["audios"][0]["title"], "cached-title");
        // Alter a file without adding or removing a directory entry.
        wav(&file, 1600);
        _refresh_index(&mut index, |_| {}).unwrap();
        assert_eq!(index["folders"][0]["audios"][0]["size"], 3244);
        assert_ne!(index["folders"][0]["audios"][0]["title"], "cached-title");
        fs::remove_file(file).unwrap();
        _refresh_index(&mut index, |_| {}).unwrap();
        assert_eq!(index["folders"][0]["audios"].as_array().unwrap().len(), 0);
    }
    #[test]
    fn retains_offline_folders_and_deduplicates_overlapping_roots() {
        let fixture = Fixture::new();
        wav(&fixture.0.join("song.wav"), 800);
        let mut index = fixture.index();
        index["roots"] = serde_json::json!([fixture.0.to_string_lossy(), fixture.0.to_string_lossy()]);
        _refresh_index(&mut index, |_| {}).unwrap();
        assert_eq!(index["folders"].as_array().unwrap().len(), 1);
        let moved = fixture.0.with_extension("offline");
        fs::rename(&fixture.0, &moved).unwrap();
        let result = _refresh_index(&mut index, |_| {});
        fs::rename(&moved, &fixture.0).unwrap();
        result.unwrap();
        assert_eq!(index["folders"][0]["audios"].as_array().unwrap().len(), 1);
    }
    #[test]
    fn index_replacement_keeps_a_valid_backup() {
        let fixture = Fixture::new();
        let path = fixture.0.join("index.json");
        _write_index(&path, &serde_json::json!({"version":1})).unwrap();
        _write_index(&path, &serde_json::json!({"version":2})).unwrap();
        let backup: serde_json::Value = serde_json::from_slice(&fs::read(path.with_extension("json.bak")).unwrap()).unwrap();
        assert_eq!(backup["version"], 1);
        let current: serde_json::Value = serde_json::from_slice(&fs::read(path).unwrap()).unwrap();
        assert_eq!(current["version"], 2);
    }
}
