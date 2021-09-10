import 'package:bloc/bloc.dart';
import 'package:kiwi/kiwi.dart';
import 'package:logging/logging.dart';
import 'package:nc_photos/account.dart';
import 'package:nc_photos/entity/person.dart';
import 'package:nc_photos/entity/person/data_source.dart';

abstract class ListPersonBlocEvent {
  const ListPersonBlocEvent();
}

class ListPersonBlocQuery extends ListPersonBlocEvent {
  const ListPersonBlocQuery(this.account);

  @override
  toString() {
    return "$runtimeType {"
        "account: $account, "
        "}";
  }

  final Account account;
}

abstract class ListPersonBlocState {
  const ListPersonBlocState(this.account, this.items);

  @override
  toString() {
    return "$runtimeType {"
        "account: $account, "
        "items: List {length: ${items.length}}, "
        "}";
  }

  final Account? account;
  final List<Person> items;
}

class ListPersonBlocInit extends ListPersonBlocState {
  ListPersonBlocInit() : super(null, const []);
}

class ListPersonBlocLoading extends ListPersonBlocState {
  const ListPersonBlocLoading(Account? account, List<Person> items)
      : super(account, items);
}

class ListPersonBlocSuccess extends ListPersonBlocState {
  const ListPersonBlocSuccess(Account? account, List<Person> items)
      : super(account, items);
}

class ListPersonBlocFailure extends ListPersonBlocState {
  const ListPersonBlocFailure(
      Account? account, List<Person> items, this.exception)
      : super(account, items);

  @override
  toString() {
    return "$runtimeType {"
        "super: ${super.toString()}, "
        "exception: $exception, "
        "}";
  }

  final dynamic exception;
}

/// List all people recognized in an account
class ListPersonBloc extends Bloc<ListPersonBlocEvent, ListPersonBlocState> {
  ListPersonBloc() : super(ListPersonBlocInit());

  @override
  mapEventToState(ListPersonBlocEvent event) async* {
    _log.info("[mapEventToState] $event");
    if (event is ListPersonBlocQuery) {
      yield* _onEventQuery(event);
    }
  }

  Stream<ListPersonBlocState> _onEventQuery(ListPersonBlocQuery ev) async* {
    try {
      yield ListPersonBlocLoading(ev.account, state.items);
      yield ListPersonBlocSuccess(ev.account, await _query(ev));
    } catch (e, stackTrace) {
      _log.severe("[_onEventQuery] Exception while request", e, stackTrace);
      yield ListPersonBlocFailure(ev.account, state.items, e);
    }
  }

  Future<List<Person>> _query(ListPersonBlocQuery ev) {
    final personRepo = PersonRepo(PersonRemoteDataSource());
    return personRepo.list(ev.account);
  }

  static final _log = Logger("bloc.list_personListPersonBloc");
}