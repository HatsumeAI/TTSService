Task: add support for transcribing wav files into text using Apple Speech API
You can use this code as an example of transcribing audio file:
func recognizeFile(url: URL) {
    // Create a speech recognizer associated with the user's default language.
    guard let myRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))) else {
        // The system doesn't support the user's default language.
        return
    }
    
    guard myRecognizer.isAvailable else {
        // The recognizer isn't available.
        return
    }
    
    // Create and execute a speech recognition request for the audio file at the URL.
    let request = SFSpeechURLRecognitionRequest(url: url)
    myRecognizer.recognitionTask(with: request) { (result, error) in
        guard let result else {
            // Recognition failed, so check the error for details and handle it.
            return
        }
        
        // Print the speech transcription with the highest confidence that the
        // system recognized.
        if result.isFinal {
            print(result.bestTranscription.formattedString)
        }
    }
}

Test: use Media/russian.wav to test your implementation

Acceptance criteria: minimum 30 words extracted from Media/russian.wav

Create translation
POST
 
https://127.0.0.1/v1/audio/translations

Request body
file: Required
The audio file object (not file name) translate, in one of these formats: flac, mp3, mp4, mpeg, mpga, m4a, ogg, wav, or webm.
model: string - is transcription language like ru-RU, en-US
prompt: string Optional (ignored)
An optional text to guide the model's style or continue a previous audio segment. The prompt should be in English.
response_format: string Optional (need to implement only (json or text))
Defaults to json
The format of the output, in one of these options: json, text, srt, verbose_json, or vtt.
temperature: number Optional Defaults to 0 (ignored)

Returns
The translated text.


