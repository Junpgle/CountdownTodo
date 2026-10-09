import '../models.dart';

/// Search domains shared by the overlay and its data-source adapters.
enum SearchScope {
  all('全部', {}),
  todos('待办', {SearchResultType.todo, SearchResultType.todoGroup}),
  schedule('日程', {
    SearchResultType.course,
    SearchResultType.fixedSchedule,
    SearchResultType.planBlock,
  }),
  finance('记账', {SearchResultType.finance}),
  focus('专注与时间', {SearchResultType.log, SearchResultType.tag}),
  countdowns('倒计时', {SearchResultType.countdown}),
  habits('习惯', {SearchResultType.habit, SearchResultType.habitCheckIn}),
  challenges('挑战', {
    SearchResultType.challenge,
    SearchResultType.challengeTask,
    SearchResultType.challengeTemplate,
  }),
  screenTime('屏幕时间', {SearchResultType.app}),
  teams('团队', {SearchResultType.team}),
  journal('日记', {SearchResultType.journal}),
  chat('AI 对话', {SearchResultType.chat}),
  settings('设置与操作', {SearchResultType.setting, SearchResultType.action});

  const SearchScope(this.label, this.types);

  final String label;
  final Set<SearchResultType> types;

  bool includes(SearchResultType type) => this == all || types.contains(type);

  bool includesAny(Iterable<SearchResultType> types) => types.any(includes);

  static const common = [all, todos, schedule, finance, focus];
}

/// Observes logical source invocations, rather than individual SQL statements.
typedef SearchSourceObserver = void Function(String source);
