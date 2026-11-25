# The agreed six labs, in order. Shared by Test-ContentPack.ps1 and ContentPack.Tests.ps1.
@{
    Labs = @(
        @{ N = '01'; Name = 'Build it (basic)'; Dir = '01-build-basic' }
        @{ N = '02'; Name = 'Build it (advanced, with advanced RAG)'; Dir = '02-build-advanced' }
        @{ N = '03'; Name = 'Evaluate it'; Dir = '03-evaluate' }
        @{ N = '04'; Name = 'Deploy it'; Dir = '04-deploy' }
        @{ N = '05'; Name = 'Integrate it'; Dir = '05-integrate' }
        @{ N = '06'; Name = 'Govern it'; Dir = '06-govern' }
    )
}
