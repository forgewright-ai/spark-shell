//! A wav file in the microphone's place: 16-bit PCM, the first channel, at its own rate.

use std::io::{Read, Seek, SeekFrom};

pub struct Wav {
    file: std::fs::File,
    rate: u32,
    channels: u16,
    left: u64,
}

fn u16_at(b: &[u8], i: usize) -> u16 {
    u16::from_le_bytes([b[i], b[i + 1]])
}
fn u32_at(b: &[u8], i: usize) -> u32 {
    u32::from_le_bytes([b[i], b[i + 1], b[i + 2], b[i + 3]])
}

impl Wav {
    pub fn open(path: &str) -> Result<Wav, String> {
        let mut file = std::fs::File::open(path).map_err(|e| format!("{path}: {e}"))?;
        let mut head = [0u8; 12];
        file.read_exact(&mut head).map_err(|e| format!("{path}: {e}"))?;
        if &head[0..4] != b"RIFF" || &head[8..12] != b"WAVE" {
            return Err(format!("{path}: not a wav file"));
        }
        let (mut rate, mut channels, mut bits) = (0u32, 0u16, 0u16);
        loop {
            let mut chunk = [0u8; 8];
            file.read_exact(&mut chunk).map_err(|_| format!("{path}: no data chunk"))?;
            let size = u64::from(u32_at(&chunk, 4));
            match &chunk[0..4] {
                b"fmt " => {
                    let mut fmt = vec![0u8; size as usize];
                    file.read_exact(&mut fmt).map_err(|e| format!("{path}: {e}"))?;
                    channels = u16_at(&fmt, 2);
                    rate = u32_at(&fmt, 4);
                    bits = u16_at(&fmt, 14);
                }
                b"data" => {
                    if bits != 16 || channels == 0 || rate == 0 {
                        return Err(format!("{path}: 16-bit PCM only"));
                    }
                    return Ok(Wav {
                        file,
                        rate,
                        channels,
                        left: size,
                    });
                }
                _ => {
                    file.seek(SeekFrom::Current((size + size % 2) as i64)).map_err(|e| format!("{path}: {e}"))?;
                }
            }
        }
    }

    pub fn rate(&self) -> u32 {
        self.rate
    }

    /// The next frames, the first channel of each, into `out`: how many; 0 at the end.
    pub fn read(&mut self, out: &mut [i16]) -> usize {
        let frame = 2 * usize::from(self.channels);
        let want = (out.len() * frame).min(self.left as usize);
        let mut bytes = vec![0u8; want];
        let mut got = 0;
        while got < want {
            match self.file.read(&mut bytes[got..]) {
                Ok(0) | Err(_) => break,
                Ok(n) => got += n,
            }
        }
        self.left -= got as u64;
        let frames = got / frame;
        for (i, o) in out.iter_mut().take(frames).enumerate() {
            *o = i16::from_le_bytes([bytes[i * frame], bytes[i * frame + 1]]);
        }
        frames
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    fn write(path: &std::path::Path, rate: u32, channels: u16, frames: &[i16]) {
        let data: Vec<u8> = frames.iter().flat_map(|s| s.to_le_bytes()).collect();
        let mut f = std::fs::File::create(path).unwrap();
        f.write_all(b"RIFF").unwrap();
        f.write_all(&(36 + 4 + data.len() as u32).to_le_bytes()).unwrap();
        f.write_all(b"WAVE").unwrap();
        f.write_all(b"LIST").unwrap(); // a chunk to skip, odd-sized
        f.write_all(&3u32.to_le_bytes()).unwrap();
        f.write_all(b"abc\0").unwrap();
        f.write_all(b"fmt ").unwrap();
        f.write_all(&16u32.to_le_bytes()).unwrap();
        f.write_all(&1u16.to_le_bytes()).unwrap();
        f.write_all(&channels.to_le_bytes()).unwrap();
        f.write_all(&rate.to_le_bytes()).unwrap();
        f.write_all(&(rate * u32::from(channels) * 2).to_le_bytes()).unwrap();
        f.write_all(&(channels * 2).to_le_bytes()).unwrap();
        f.write_all(&16u16.to_le_bytes()).unwrap();
        f.write_all(b"data").unwrap();
        f.write_all(&(data.len() as u32).to_le_bytes()).unwrap();
        f.write_all(&data).unwrap();
    }

    #[test]
    fn a_stereo_wav_reads_its_first_channel_past_other_chunks() {
        let dir = std::env::temp_dir().join(format!("spark-ear-wav-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("t.wav");
        write(&path, 8000, 2, &[1, -1, 2, -2, 3, -3]);
        let mut w = Wav::open(path.to_str().unwrap()).unwrap();
        assert_eq!(w.rate(), 8000);
        let mut buf = [0i16; 2];
        assert_eq!(w.read(&mut buf), 2);
        assert_eq!(buf, [1, 2]);
        assert_eq!(w.read(&mut buf), 1);
        assert_eq!(buf[0], 3);
        assert_eq!(w.read(&mut buf), 0);
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn not_a_wav_is_refused() {
        let dir = std::env::temp_dir().join(format!("spark-ear-wav-no-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("t.txt");
        std::fs::write(&path, b"hello hello hello").unwrap();
        assert!(Wav::open(path.to_str().unwrap()).err().unwrap().ends_with("not a wav file"));
        std::fs::remove_dir_all(dir).unwrap();
    }
}
