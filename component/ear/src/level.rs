//! The loudness of a block of samples, 0 to 7, for the bars on the band.

/// 0 at silence, 7 near full scale: the RMS in decibels, from -54 dB up in steps of 6.
pub fn level(samples: &[i16]) -> u8 {
    if samples.is_empty() {
        return 0;
    }
    let sum: f64 = samples
        .iter()
        .map(|&s| {
            let x = f64::from(s) / 32768.0;
            x * x
        })
        .sum();
    let rms = (sum / samples.len() as f64).sqrt();
    if rms <= 0.0 {
        return 0;
    }
    let db = 20.0 * rms.log10();
    ((db + 54.0) / 6.0).floor().clamp(0.0, 7.0) as u8
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tone(amplitude: f64) -> Vec<i16> {
        (0..1600).map(|i| (amplitude * 32767.0 * (i as f64 * 0.1).sin()) as i16).collect()
    }

    #[test]
    fn silence_is_zero_and_full_scale_is_seven() {
        assert_eq!(level(&[]), 0);
        assert_eq!(level(&[0; 1600]), 0);
        assert_eq!(level(&tone(1.0)), 7);
    }

    #[test]
    fn speech_sits_in_the_middle() {
        assert_eq!(level(&tone(0.05)), 4); // -29 dB
        assert_eq!(level(&tone(0.002)), 0); // -57 dB, the noise floor
    }
}
