# Product requirements log

This file stores decisions confirmed by the product owner. Each questionnaire batch is appended with the date, original question, answer, and resulting implementation decision.

## Confirmed decisions before questionnaire

- Show every inventory document available in MoySklad in the inventory section.
- Fetch remote MoySklad inventories and their positions on demand; do not permanently store their remote data in the app's local database.
- Allow editing inventory records/positions in MoySklad.
- Record local inventory draft creation/deletion, submission, remote edits, and failures in the warehouse journal as a chronological event history.
- Keep unsent local drafts on-device for offline continuation.
