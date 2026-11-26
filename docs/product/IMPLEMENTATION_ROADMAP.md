# Product decisions and implementation roadmap

## Confirmed inventory workflow

- The inventory section must show all inventory documents currently available in MoySklad, not only documents created by Lerua Zakup.
- MoySklad inventory documents are fetched on demand from the API. Their remote document and position data are not copied into permanent local application tables.
- Local, not-yet-sent inventory drafts remain local so that counting can continue after the app is closed or the device loses connectivity.
- Users can open a MoySklad inventory and edit its existing positions. Position updates are sent to the MoySklad position endpoint through the durable API task queue.
- A remote edit is confirmed only after the API task succeeds. If the result is uncertain, the app must ask the user to refresh the document before retrying rather than silently sending the write again.
- Local draft creation, deletion, submission to MoySklad, remote position edits, and synchronization failures are recorded as timestamped events in the warehouse journal.
- The warehouse journal keeps one timeline per inventory operation; events are appended instead of replacing the previous history.

## Inventory event vocabulary

| Event | User-facing journal text |
| --- | --- |
| `draft_created` | Создан локальный черновик инвентаризации |
| `draft_deleted` | Локальный черновик инвентаризации удалён |
| `sent_to_moysklad` | Инвентаризация создана в МойСклад |
| `position_updated` | Изменена позиция инвентаризации |
| `sync_failed` | Не удалось отправить инвентаризацию в МойСклад |

## Implementation roadmap

### In progress — live MoySklad inventories

1. List remote inventory documents from MoySklad alongside local drafts.
2. Fetch positions on demand; do not persist remote documents locally.
3. Edit existing positions via the MoySklad API and the durable write queue.
4. Keep an audit timeline in the warehouse journal.
5. Add repository, transport, dispatcher, journal, and UI tests.

### Next

- Verify API permissions and real-account behavior against a live MoySklad account.
- Review inventory status transitions, editing restrictions, and handling of documents already posted/closed in MoySklad.
- Expand inventory editing to any additional document fields and position operations confirmed by the product questionnaire.
- Continue product discovery in batches of 10 questions. Record each answer here and in the requirements log, update the roadmap, and derive the next questions from unanswered decisions. Do not ask already answered questions again.

## Questionnaire protocol

- Ask exactly 10 concise, numbered questions per batch.
- Prefer concrete scenarios and clear answer choices, but allow free-form answers.
- After the user's answers, append them to `docs/product/requirements-log.md`.
- Update this roadmap with the decisions and implementation consequences.
- Ask the next batch only after recording the previous answers; avoid duplicates.

## Confirmed purchase/order/transfer decisions — questionnaire round 1 (2026-11-26)

- Include all active products carrying the matching operation flag, regardless of stock.
- Process selected warehouses sequentially, completing one warehouse before moving to the next.
- Select warehouses without restricting storage locations; include all locations under each selected warehouse.
- Show the total stock for the selected warehouse.
- Enter additional purchase/order quantity; current stock is informational, not subtracted from the entered quantity.
- Products without a supplier are grouped into a separate “Без поставщика” calendar record.
- Multiple product flags create independent operations for each selected type.
- Create one supplier record per warehouse; list its storage locations inside that record rather than splitting by location.
- Preserve incomplete entry as a resumable local draft.
- Generate an independent sequential number for each operation type.

Implementation implications: product filtering must be flag-driven; entry sessions must be warehouse-sequential; draft persistence must survive app restarts; calendar grouping key is operation type + warehouse + supplier (including the no-supplier bucket); sequence counters are scoped by operation type.
