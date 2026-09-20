# Pocket Canvas privacy policy

Effective date: September 21, 2026.

Pocket Canvas is an experimental app for evaluating image generation and editing on an iPhone. The app does not include advertising, tracking, analytics SDKs, a user account system, or a developer-operated inference server.

Prompts, selected reference photos, generated images, settings, and run diagnostics are processed and stored on the device. Generation and editing do not send them to a server. History can be deleted within the app. Removing the app removes its local container; copies you export elsewhere are managed by those destinations. Depending on your device settings, iOS may include app history in device backups. Downloaded model files are excluded from backup.

When you explicitly install model files, the app connects to Hugging Face and its download infrastructure. Those services receive the network information needed to serve the files, including your IP address and requested model-file URLs. Their handling of that information is governed by their own privacy policies. The app does not send your prompts or photos with these requests.

Photos access is requested when you choose to save an image. Reference photos are selected through the system photo picker. Sharing an image or diagnostic report uses the iOS share sheet and sends the selected content only to a destination you choose. Diagnostic reports may contain device and operating-system information, model versions, performance measurements, thermal state, and error details. Review reports before sharing them.

Apple may process TestFlight feedback and crash information under its own privacy terms. This is separate from the app's local diagnostic storage.

For questions, open an issue at https://github.com/buberlo/Qwen-Image-2.1/issues. Issues are public; do not include private photos, prompts, or personal information.
