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

## Confirmed purchase/order/transfer decisions — questionnaire round 2 (2026-11-26)

- A transfer explicitly selects a source warehouse and a destination warehouse; stock leaves the source and arrives at the destination.
- Transfer product selection includes all products flagged for transfer, with a manual-add path for other products.
- Transfer calendar date is the current date.
- Calendar grouping remains one record per operation type + warehouse + supplier.
- Historical operation list shows date, number, warehouse, and supplier only.
- Existing records are viewable and can be deleted as a whole; editing individual lines is out of scope for now.
- Calendar records are created when the user presses Finish. A warehouse with no entered quantities produces no record.
- Product entry order follows storage-location order as configured in MoySklad, then alphabetical order within each location.
- Each operation line stores a snapshot of product details at creation time so later reference-data changes do not rewrite history.

Implementation implications and open safeguards:

- Model transfer source and destination explicitly and validate that they differ. Before applying stock changes, validate available source quantity and define safe behavior for insufficient stock; do not silently create negative stock.
- Keep flag-based transfer selection but provide a controlled manual-add action.
- Use the local completion date for transfer calendar entries.
- Preserve grouping by operation type, warehouse, and supplier, including the “Без поставщика” bucket from round 1.
- Keep list rows compact; detailed positions are available only after opening a record.
- Provide whole-record deletion with a confirmation step and corresponding journal/audit event; do not implement line editing yet.
- Treat Finish as the explicit commit boundary: create only non-empty warehouse/supplier groups, and avoid partial duplicate records if persistence fails midway (transaction/idempotency behavior must be designed).
- Obtain storage-location ordering from the source system rather than relying on arbitrary API order; sort product names alphabetically within each location.
- Persist immutable product snapshots (at minimum the confirmed product identity/display details and unit; finalize exact snapshot fields in a later question round).

## Confirmed purchase/order/transfer decisions — questionnaire round 3 (2026-11-26)

- Current transfer scope is calendar-only: do not create a MoySklad transfer document and do not change warehouse balances.
- The answer allowing negative stock is recorded for a possible future real transfer implementation; it has no current stock effect while transfers remain calendar-only.
- For a future real transfer, the destination storage location should be selected automatically. The product owner clarified that each product can exist in only one storage location.
- Manual additions to a transfer may include any active product, whether or not it has the Transfer flag.
- Deletion behavior for an already-created transfer remains undecided; do not assume reversal or deletion semantics.
- Immutable product snapshots contain product name, unit of measure, and supplier.
- Before completion, users may edit quantities and remove draft lines.
- If finalization fails, retain the draft and allow retry later. Retrying must be idempotent and must not duplicate calendar records already persisted.
- On success, show a concise success message only; no detailed completion summary is needed.

Implementation implications / outstanding decisions:

- Keep transfer persistence within the app's calendar/operation model only for the initial release; isolate any future MoySklad posting and stock mutation behind a later, separately approved workflow.
- Do not implement negative stock behavior in the current calendar-only transfer flow. Revisit the negative-stock decision only if actual stock posting is brought into scope.
- Since each product has one storage location, avoid UI that asks users to choose among multiple source locations for the same product. Determine the destination location automatically according to a rule still to be confirmed.
- Manual transfer search/add must include active catalog products regardless of the transfer flag.
- Keep whole-record deletion disabled or gated until the unanswered deletion policy is clarified; existing round-2 permission to delete whole records should not be treated as defining reversal behavior for transfers.
- Snapshot exactly name, unit of measure, and supplier as required historical display fields.
- Draft editing supports quantity changes and line removal. On finalization errors, preserve the draft and persist per-group completion/idempotency state so retry cannot create duplicates.
- Completion UI needs only a success confirmation.

## Confirmed purchase/order/transfer decisions — questionnaire round 4 (2026-11-26)

- Calendar operation details group products beneath supplier headings, repeating the supplier heading for each supplier group.
- Detailed operation views show product, entered quantity, unit of measure, and current stock.
- Operation numbers include operation-type prefix, year, and a sequence, e.g. З-2026-0001. Counters remain independent per operation type.
- Quantity precision follows the product's unit of measure.
- Negative purchase/order quantities are forbidden, but a warehouse stock balance may itself be negative.
- Save draft changes when advancing to the next product.
- Multiple drafts of the same operation type are allowed; users can manually delete drafts.
- If an operation flag is removed from a product after it has entered a draft, keep the product in that draft.
- Automatically use the product's single storage location in the selected warehouse.
- Drafts expire and are automatically deleted after one week; manual deletion is also supported.

Implementation implications / details still to confirm:

- Render calendar operation content as supplier-group headings with their product lines, within the established operation-type + warehouse grouping.
- Show product, operation quantity, unit, and current stock in the detail view. Preserve the immutable snapshot fields (name, unit, supplier) from round 3; current stock remains a live informational value.
- Generate human-readable identifiers from operation type + year + per-type sequence; define collision-safe allocation and year rollover.
- Derive numeric input precision from the unit metadata and reject negative entered purchase/order quantities while allowing negative stock values to be displayed.
- Persist a draft when the user navigates forward to the next product; retain resumability across app restarts.
- Support concurrent multiple drafts per operation type and manual draft deletion.
- Draft membership is stable once captured; later reference flag changes must not silently remove draft lines.
- Resolve the unique storage location for the product within the selected warehouse automatically. Define fallback behavior if the location is missing or ambiguous.
- Implement seven-day expiry and manual deletion. Clarify the expiry anchor (creation time vs. last activity) and whether users receive an expiry warning before enabling cleanup.

## Confirmed purchase/order/transfer decisions — questionnaire round 5 (2026-11-26)

- Draft expiry is seven days after draft creation; no warning is shown. Expired drafts are removed at the next app launch.
- Product lists are scoped to the selected warehouse: only products stored at that warehouse / its storage locations may appear. A product without a location in that selected warehouse is not a normal selectable case.
- Completed operation details show the stock balance captured at operation creation, not a live current balance.
- Completed operations exist only in the app calendar at this stage. Deletion removes the app's calendar record only; it does not call MoySklad. Require an irreversible-action confirmation.
- Separate operation lists are titled “Закупки”, “Заказы”, and “Перемещения”. Each list row shows date and operation number.
- Comments are not required.
- Prices and monetary totals are out of scope; track quantities only.

Implementation implications:
- Set a fixed created-at timestamp on each draft and expire it after seven days. Perform cleanup during app startup without a pre-expiry notification.
- Query/filter product candidates by selected warehouse and its storage locations; do not offer a manual storage-location fallback for products that do not belong to that warehouse.
- Store the stock balance snapshot on each operation line and render that historical value in completed operation details.
- Implement deletion as a local calendar/operation deletion only, with an explicit confirmation dialog. Do not enqueue MoySklad API mutations.
- Provide separate type-specific list screens/filters and show only date + formatted operation number in list rows.
- Omit comment fields, prices, and monetary calculations from this feature scope.
