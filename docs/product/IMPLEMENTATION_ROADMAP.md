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


## Confirmed purchase/order/transfer decisions — questionnaire round 6 (2026-11-26)

- The creation flow allows selecting multiple warehouses in one selection step. Quantities remain independent for each warehouse; the existing sequential warehouse-by-warehouse product workflow is retained.
- For the same product at multiple warehouses, enter a separate quantity for each warehouse.
- Purchase operations are dated today; order operations are dated tomorrow. The previously confirmed transfer date remains today.
- New quantity fields start empty. A skipped product remains skipped when revisited until the user explicitly enters a quantity; do not auto-fill zero or restore an old quantity.
- Capture the final product and stock snapshots at Finish, not when the draft is first created. This supersedes the earlier general snapshot timing decision.
- Resolve supplier from the current reference data at Finish. If the supplier changed while the draft was open, use the new supplier for the final operation and supplier grouping.
- Manual draft deletion requires a confirmation dialog. This does not change the already-confirmed silent automatic expiry cleanup at app startup.
- Opening an operation from the calendar goes directly to its product list grouped by supplier, without an intermediate summary card.
- The default entry mode is one product at a time with a Next button. A table/list entry mode is not approved at this stage.

Implementation implications / updated priorities:

1. **Creation flow and warehouse scope**
   - Add multi-select warehouse selection to the initial step.
   - Preserve per-warehouse quantities and per-warehouse operation grouping; never merge quantities for the same product across warehouses.
   - Keep the agreed sequential product-entry flow for each selected warehouse, moving to the next warehouse after completing/skipping the current one.
2. **Quantity entry**
   - Initialize quantity inputs as empty/null, not zero.
   - Treat an untouched/blank or skipped line as absent from the completed operation.
   - When navigating back to a skipped product, leave its field empty until the user enters a quantity.
   - Keep existing unit-dependent precision and non-negative purchase/order quantity validation.
3. **Finish-time snapshots and supplier resolution**
   - At Finish, obtain the final product name, unit, supplier, and warehouse stock snapshot from the then-current source data and persist them immutably with the operation lines.
   - Use the current supplier reference at Finish for grouping; do not freeze the supplier when the draft is created.
   - The historical stock shown in completed operation details is the Finish-time snapshot. This explicitly overrides round 5's earlier wording that described the snapshot as being taken at operation creation.
   - Keep Finish atomic/idempotent: if persistence fails, retain the draft and allow retry without duplicate calendar records.
4. **Navigation and deletion**
   - Calendar does not navigate to a separate operation screen. Supplier/warehouse groups and their collapsed product lists render inline in the calendar; users expand/collapse them in place.
   - Add a confirmation step for manual draft deletion. Keep the already agreed expiry policy: delete drafts older than seven days at next app startup without warning.
   - Completed operation deletion remains local-only and requires confirmation as agreed in round 5.
5. **Entry UI**
   - Implement single-product-at-a-time entry with a Next action as the primary and only currently approved mode.
   - Do not add a list/table mode unless the product owner approves it in a later round.

### Remaining discovery before implementation

The six rounds establish the core workflow. Before coding, clarify remaining edge cases and acceptance details, especially:
- exact date/time boundary and timezone behavior for “today” and “tomorrow”;
- how to handle supplier changes or deleted supplier references between draft creation and Finish;
- behavior if a selected warehouse becomes unavailable or a product loses its warehouse/storage-location association while a draft is open;
- how a user navigates between warehouses and resumes a multi-warehouse draft;
- whether zero is a valid explicitly entered quantity or should be treated as skipped;
- operation numbering prefix mapping for all three operation types and year rollover;
- transfer-specific representation of source/destination in calendar records, given that transfers are calendar-only;
- confirmation and error handling details for Finish and deletion.

Do not begin feature implementation until the remaining critical decisions are recorded and a concrete implementation plan is approved.


## Уточнение после раунда 6 — календарь не открывает отдельные экраны (2026-11-26)

Последнее уточнение пользователя заменяет прежнюю трактовку пункта 9 раунда 6. **Не делать переход из календаря в карточку, экран операции или отдельный список товаров.** Календарь остаётся местом просмотра содержимого.

- При входе в календарь автоматически выбрана сегодняшняя дата.
- При выборе любой даты её содержимое показывается прямо в области календаря для выбранного дня.
- Каждая группа отображается заголовком вида «Поставщик 1 на склад 1», под которым находится свёрнутый список товаров; следующая группа — «Поставщик 1 на склад 2» и так далее.
- Раскрытие/сворачивание списка товаров происходит прямо в календаре, без навигации.
- Группировка сохраняет согласованные измерения: тип операции, склад и актуальный поставщик; визуальный заголовок календарной группы должен явно показывать поставщика и склад.
- Пошаговый ввод товара с кнопкой «Далее» применяется только при создании операции и не является режимом просмотра календаря.

Удалить из требований и реализации прежнее поведение «нажать на операцию в календаре и открыть список товаров». Никакого отдельного экрана просмотра завершённой операции в рамках этого сценария не создавать.


## Confirmed purchase/order/transfer decisions — questionnaire round 7 (2026-11-26)

- Use the device's local timezone to calculate operation dates.
- The operation date is fixed when the draft is created; finishing after midnight does not change it.
- If a supplier reference has been deleted or is unavailable at Finish, group the product under “Без поставщика”.
- If a selected warehouse becomes unavailable while a draft is open, retain it and allow Finish.
- If a product is no longer listed under the selected warehouse at Finish, use the last known product/warehouse data retained in the draft rather than silently dropping the line.
- An explicitly entered quantity of zero is equivalent to skipping and is omitted from the completed operation.
- Resume a multi-warehouse draft automatically at the last unfinished warehouse and product.
- Operation number prefixes are user-defined: Закупка = ЗУП, Заказ = ЗАЗ, Перемещение = ПЕР.
- Number sequences reset each year and are independent per operation type and year.
- Transfers have no supplier. Calendar representation identifies only the source and destination warehouses.

Implementation implications:
- Derive “today” and “tomorrow” from the device-local date. Persist the operation date in the draft at creation so a draft crossing midnight retains its original date.
- Resolve deleted/missing supplier references to the “Без поставщика” group at Finish.
- Do not invalidate a draft or prevent Finish solely because a selected warehouse is currently unavailable. Preserve the selected warehouse identity and last known draft context.
- Keep the last known product and warehouse association in draft data so Finish can still create the operation line if the live catalog no longer returns that association. Capture the agreed historical product/unit/stock snapshot at Finish from available data, falling back to the draft's last known values where live data is unavailable.
- Normalize zero quantity to skipped/absent; no zero-quantity operation lines.
- Persist a resumable cursor (warehouse + product) and restore it automatically.
- Format identifiers with prefixes ЗУП, ЗАЗ, ПЕР, year, and a per-type/per-year sequence. Reset each sequence on year rollover.
- Calendar grouping for purchase/order remains supplier + warehouse. Transfer grouping is separate and supplier-free: source warehouse → destination warehouse, with the transfer products listed beneath. Transfers remain calendar-only and do not mutate MoySklad stock.

### Remaining discovery before implementation — after round 7

Still to clarify:
- exact presentation details for manual additions to transfer (the scope is already decided: flagged products plus manual addition of any active product);
- exact Finish transaction/idempotency behavior and user-facing retry/error states;
- completed calendar record deletion behavior specific to transfer (whole local record deletion was agreed generally, but confirm if any transfer-specific exception is needed);
- whether operation sequence allocation must be synchronized across devices or is device-local;
- final acceptance criteria and approval of the concrete implementation plan.

Already resolved by rounds 6–7: date timezone and date anchor, missing/deleted supplier, unavailable warehouse/product behavior, zero quantity, multi-warehouse resume point, numbering prefixes/year reset, transfer calendar grouping, and inline calendar behavior.


## Раунд 7 — уточнение представления перемещения в календаре (2026-11-26)

- Выбран вариант C: отдельная группа с явным заголовком **«Перемещение: склад-источник → склад-получатель»**.
- У перемещения нет поставщика. Не использовать поставщика ни как поле группировки, ни как часть заголовка.
- Под заголовком размещать свёрнутый список товаров; раскрытие выполняется непосредственно в календаре, без перехода на отдельный экран.
- Явное слово «Перемещение» предпочтительнее краткого заголовка только со стрелкой: оно однозначно отличает запись перемещения от закупки или заказа.


## Раунд 8 — завершение операций и дополнительные правила (2026-11-26)

- Нумерация локальная: один пользователь и одно устройство; не нужна синхронизация номеров между устройствами или отправка номера на сервер. Сохранять независимые локальные счётчики по типу и году.
- Список черновиков показывает дату и номер.
- При возобновлении пропускать товары, удалённые из актуального справочника, и переходить к следующему доступному товару. Уже введённые строки сохраняют ранее согласованный последний известный контекст.
- Finish атомарный: при ошибке откатываются все группы, частично завершённая операция не остаётся. Черновик сохраняется.
- Повтор доступен и кнопкой «Повторить» на экране ошибки, и повторным открытием черновика из списка.
- Ошибка показывает короткое понятное объяснение с раскрываемыми техническими подробностями.
- Удаление завершённого перемещения — только локальное удаление календарной записи приложения, без мутаций МойСклад.
- Несколько перемещений за день между той же парой складов отображаются отдельными группами.
- Сортировка записей выбранного дня — по времени создания.
- Пустой день показывает «Нет операций за этот день».

### Обновлённые технические требования

1. Реализовать транзакционное завершение: создание всех календарных групп и строк одной операции выполняется в одной локальной транзакции. Любая ошибка приводит к rollback; черновик остаётся доступным для повтора.
2. Сохранять точный timestamp создания операции для сортировки записей внутри выбранного дня; дата операции по-прежнему фиксируется при создании черновика согласно раунду 7.
3. Для возобновления черновика пропускать недоступные в текущем справочнике товары, не удаляя и не теряя уже введённые строки/их снимки.
4. В UI ошибки предусмотреть краткое описание и раскрытие технических деталей, а также действие повтора.
5. В списке черновиков показывать дату и номер; обеспечить открытие черновика и продолжение с сохранённой позиции.
6. Для перемещений не применять группировку по поставщику. Каждое завершённое перемещение — самостоятельная календарная запись с source/destination и списком товаров.

### Оставшиеся вопросы перед утверждением плана

- Уточнить визуальное представление ручного добавления товара в перемещение (само правило включения флажковых товаров плюс ручное добавление любого активного товара уже утверждено).
- Утвердить окончательные критерии приёмки и конкретный план реализации.

Вопросы о синхронизации номеров, частичном Finish, повторе, удалении перемещений, сортировке календаря и пустом дне закрыты раундом 8.
