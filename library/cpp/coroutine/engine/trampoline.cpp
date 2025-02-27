#include "impl.h"
#include "trampoline.h"

#include "stack/stack_allocator.h"

#include <util/system/info.h>
#include <util/system/protect.h>
#include <util/system/valgrind.h>
#include <util/system/yassert.h>

#include <cstdlib>
#include <util/stream/format.h>


namespace NCoro {

    TTrampoline::TTrampoline(NStack::IAllocator& allocator, ui32 stackSize, TContFunc f, TCont* cont, void* arg) noexcept
        : Stack_(allocator, stackSize, cont->Name())
        , Clo_{this, Stack_.Get(), cont->Name()}
        , Ctx_(Clo_)
        , Func_(f)
        , Cont_(cont)
        , Arg_(arg)
    {}

    void TTrampoline::DoRun() {
        if (Cont_->Executor()->FailOnError()) {
            Func_(Cont_, Arg_);
        } else {
            try {
                Func_(Cont_, Arg_);
            } catch (...) {}
        }

        Cont_->Terminate();
    }

    TArrayRef<char> TTrampoline::Stack() noexcept {
        return Stack_.Get();
    }

    const char* TTrampoline::ContName() const noexcept {
        return Cont_->Name();
    }

    void TTrampoline::DoRunNaked() {
        DoRun();

        abort();
    }
}
